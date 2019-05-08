#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

DEFAULT_IPV4=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')

function valid_ip {
    local  ip=$1
    local  stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

#arguments
function showhelp {
   echo ""
   echo "Usage examples:"
   echo "Online: $0 --inventory inventory/local/hosts.ini"
   echo "Airgap: $0 --inventory inventory/local/hosts.ini --airgap --repository http://[[ LOCAL_APT_REPO_IP_ADDRESS ]]:8080/ --metallb-range '10.5.0.50-10.5.0.99'"
   echo ""
   echo "OPTIONS:"
   echo "  [-i|--inventory path] Ansible inventory file path (required)"
   echo "  [-r|--repository address] Manually specify APT repository address (default: default route ipv4 address)"
   echo "  [-a|--airgap] Airgap installation mode (default: false)"
   echo "  [-m|--metallb-range] Deploy MetalLB layer 2 load-balancer and specify its IP range (default: false)"
   echo "  [--skip-kubespray] Skip Kubespray playbook (default: false)"
   echo "  [-h|--help] Display this usage message"
   echo ""
}

## Defaults
airgap="false"
airgap_bool='{airgap: False}'
metallb="false"
skip_kubespray="false"

## Deploy
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|help|--help)
        showhelp
        exit 0
        ;;
        -r|--repository)
        shift
        repository_address="$1"
        shift
        continue
        ;;
        -a|--airgap)
        shift
        airgap="true"
        airgap_bool='{airgap: True}'
        continue
        ;;
        -m|--metallb-range)
        shift
        metallb="true"
	metallb_vars="{'metallb':{'ip_range':'$1','limits':{'cpu':'100m','memory':'100Mi'},'port':'7472','version':'v0.7.3'}}"
	shift
        continue
        ;;
        --skip-kubespray)
        shift
        skip_kubespray="true"
        continue
        ;;
        -i|--inventory)
        shift
        inventory="$1"
        shift
        continue
        ;;
    esac
    break
done

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root"
   exit 1
fi

if [ -z "$inventory" ]; then
   echo ""
   echo "ERROR: Inventory file is not specified"
   showhelp
   exit 1
fi

if [ -z "$repository_address" ] && [ $airgap == "true" ]; then
    if valid_ip $DEFAULT_IPV4; then
        repository_address="http://$DEFAULT_IPV4:8080/"
    else
        echo ""
        echo "ERROR: Unable to retrieve a valid default ipv4 address, please specify the APT repository address manually using the --repository option"
        showhelp
        exit 1
    fi
fi

echo ""
echo "===== Making sure that all dependencies are installed, please wait..."

if [ -x "$(command -v apt-get)" ]; then

	# install python, pip and sshpass
	dpkg-query -l python python-pip python-netaddr sshpass > /dev/null 2>&1
	if [ $? != 0 ]; then
	    set -e
	    apt-get -qq update > /dev/null
	    apt-get -qq install -y --no-install-recommends python python-pip python-netaddr sshpass > /dev/null
	    set +e
	fi
elif [ -x "$(command -v yum)" ]; then
     #Enable epel-release
     subscription-manager repos --enable=rhel-7-server-extras-rpms
     yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	for package in \
		python \
		python-pip \
		python-netaddr \
		sshpass \
	; do
		yum list installed "$package" > /dev/null 2>&1
	        if [ $? != 0 ]; then
		   set -e
		   yum install -q -y $package > /dev/null
		   set +e
		fi
	done
fi

# install ansible
set -e
pip install --quiet --no-index --find-links ./pip_deps/ setuptools
pip install --quiet --no-index --find-links ./pip_deps/ -r requirements.txt
set +e

if [ $airgap == "true" ]; then
    echo "===== Airgap installation mode: Yes"
    echo "===== Using APT repository address: $repository_address"
else
    echo "===== Airgap installation mode: No"
fi
echo ""

# run ansible playbook
export ANSIBLE_FORCE_COLOR=True
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_PIPELINING=True

if [ ! $skip_kubespray == "true" ]; then
    ansible-playbook -vv -i "$inventory" \
      --become --become-user=root \
      -e "$airgap_bool" \
      -e repository_address="$repository_address" \
      $BASEDIR/cluster.yml "$@"
fi

if [ $metallb == "true" ]; then
    ansible-playbook -vv -i "$inventory" \
      --become --become-user=root \
      -e "$metallb_vars" \
      $BASEDIR/contrib/metallb/metallb.yml "$@"
fi
