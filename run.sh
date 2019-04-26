#!/bin/bash

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
   echo "Airgap: $0 --inventory inventory/local/hosts.ini --airgap --repository http://[[ LOCAL_APT_REPO_IP_ADDRESS ]]:8080/"
   echo ""
   echo "OPTIONS:"
   echo "  [-i|--inventory path] Ansible inventory file path (required)"
   echo "  [-r|--repository address] Manually specify APT repository address (default: default route ipv4 address)"
   echo "  [-a|--airgap] Airgap installation mode (default: false)"
   echo "  [-h|--help] Display this usage message"
   echo ""
}

## Defaults
airgap="false"
airgap_bool='{airgap: False}'

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

# install python and pip
dpkg-query -l python python-pip python-netaddr > /dev/null 2>&1
if [ $? != 0 ]; then
    apt-get update
    apt-get install -y --no-install-recommends python python-pip python-netaddr
fi
if [ $airgap == "true" ]; then
    dpkg-query -l ansible sshpass > /dev/null 2>&1
    if [ $? != 0 ]; then
        apt-get update
        apt-get install -y --no-install-recommends ansible sshpass
    fi
else
    pip freeze | grep -i ansible > /dev/null 2>&1
    if [ $? != 0 ]; then
      pip install setuptools wheel
      pip install -r requirements.txt
    fi
fi

echo ""
echo ""
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

ansible-playbook -vv -i "$inventory" \
  --become --become-user=root \
  -e "$airgap_bool" \
  -e repository_address="$repository_address" \
  cluster.yml "$@"
