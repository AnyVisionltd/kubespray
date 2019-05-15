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

get_kubernetes_repo(){
    k8s_manifests_dir="/opt/kubernetes"    
    kubernetes_ver=${kubernetes_version:-1.22.0.3}

    #if kubernetes maniferst already exist and not empty dir
    if [ -d ${k8s_manifests_dir}/${kubernetes_ver} ] && [ "$(ls -A ${k8s_manifests_dir}/${kubernetes_ver})" ] ; then
        echo "the kubernetes dir ${k8s_manifests_dir}/${kubernetes_ver} is already exist. skipping get kubernetes repo..."
    elif [ $airgap == "true" ] ; then
        echo "airgap mode is on. skipping get kubernetes repo..."
    else #if kubernetes maniferst is not exist
        # exit if not provided any token 
        if [ -z "$tokenkey" ]; then
            echo ""
            echo "ERROR: Token is not specified."
            showhelp
            exit 1
        elif [[ $tokenkey != "" ]] && [[ $tokenkey == *".json" ]] && [[ -f $tokenkey ]] ;then
            echo "detected gcr json key file: $tokenkey"
            gcr_user="_json_key" 
            gcr_key="$(cat ${tokenkey} | tr '\n' ' ')"
        elif  [[ $tokenkey != "" ]] && [[ ! -f $tokenkey ]] && [[ $tokenkey != *".json" ]]; then
            echo "detected gcr token: $tokenkey"
            gcr_user="oauth2accesstoken"
            gcr_key=$tokenkey
        fi

        echo "Login to gcr.io"       
        docker login "https://gcr.io" --username "${gcr_user}" --password "${gcr_key}"
        image_name=gcr.io/${gcr_account:-anyvision-production}/kubernetes:${kubernetes_ver}
        echo "Pulling kubernetes container repo: ${image_name}"
        set -e
        docker pull $image_name
        id=$(docker create $image_name)
        mkdir -p ${k8s_manifests_dir}/${kubernetes_ver}
        docker cp $id:/kubernetes/. ${k8s_manifests_dir}/${kubernetes_ver}
        docker rm -v $id
        set +e
    fi

    #deploy app
    deploy_app
}

deploy_app(){

    echo "deploy app"
    cd ${k8s_manifests_dir}/${kubernetes_ver}/templates/
    if [ $airgap == "true" ] ; then
        ./deployer.sh -b
    else
        ./deployer.sh -k "${tokenkey}" -b
    fi
}


#arguments
function showhelp {
   echo ""
   echo "Usage examples:"
   echo "Online: $0 --inventory inventory/local/hosts.ini --key < gcr.io token (string) or json key file path > "
   echo "Airgap: $0 --inventory inventory/local/hosts.ini --airgap --repository http://[[ LOCAL_APT_REPO_IP_ADDRESS ]]:8085/"
   echo "Metallb: $0 --inventory inventory/local/hosts.ini --metallb-range '10.5.0.50-10.5.0.99'"
   echo ""
   echo "OPTIONS:"
   echo "  [-i|--inventory path] Ansible inventory file path (required)"
   echo "  [-r|--repository address] Manually specify APT repository address (default: default route ipv4 address)"
   echo "  [-a|--airgap] Airgap installation mode (default: false)"
   echo "  [--metallb-range] Deploy MetalLB layer 2 load-balancer and specify its IP range (default: false)"
   echo "  [--skip-kubespray] Skip Kubespray playbook (default: false)"
   echo "  [-h|--help] Display this usage message"
   echo "  [-k|--key] Provide a gcr.io registry token key (string) or json key file (json file path)"
   echo "  [--skip-kubernetes-manifest] Skip deploy kubernetes manifests (default: false)"
   echo "  [-v|--version] Provide version for kubernetes manifests repository"
   echo ""
}

## Defaults
airgap="false"
airgap_bool='{airgap: False}'
metallb="false"
skip_kubespray="false"
skip_kubernetes_manifest="false"

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
        -v|--version|--version)
        shift
        kubernetes_version="$1"
        shift
        continue
        ;;
        -k|key|--key)
        shift
        tokenkey="$1"
        shift
        continue
        ;;
        skip-kubespray|--skip-kubespray)
        shift
        skip_kubespray="true"
        continue
        ;;
        skip-kubernetes-manifest|--skip-kubernetes-manifest)
        shift
        skip_kubernetes_manifest="true"
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

if [ -z "$inventory" ] && [ ! $skip_kubespray == "true" ] &&  [ $metallb == "true" ]; then
   echo ""
   echo "ERROR: Inventory file is not specified"
   showhelp
   exit 1
fi

if [ $skip_kubernetes_manifest == "false" ] && [ -z "$tokenkey" ] && [ "$airgap" == "false" ]; then
   echo "ERROR: GCR key is not specified"
   showhelp
   exit 1
fi

if [ -z "$repository_address" ] && [ $airgap == "true" ]; then
    if valid_ip $DEFAULT_IPV4; then
        repository_address="http://$DEFAULT_IPV4:8085/"
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
    
    #curl -O https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    #rpm -i --force ./epel-release-latest-7.noarch.rpm
    #grep -q  'Workstation' /etc/redhat-release
    #if [ $? -eq 0 ] ; then
    #   if ! rpm --quiet --query container-selinux; then
    #      sudo rpm -ihv http://ftp.riken.jp/Linux/cern/centos/7/extras/x86_64/Packages/container-selinux-2.9-4.el7.noarch.rpm
    #   fi
    #fi
    yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sudo yum install -y python-pip git yum pciutils ansible

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
    ansible-playbook -i "$inventory" \
      --become --become-user=root \
      -e "$airgap_bool" \
      -e repository_address="$repository_address" \
      $BASEDIR/cluster.yml -vv "$@"
else
    echo "skip kubespray"
fi

if [ $metallb == "true" ]; then
    echo "deploy metallb"
    ansible-playbook -i "$inventory" \
      --become --become-user=root \
      -e "$metallb_vars" \
      $BASEDIR/contrib/metallb/metallb.yml -vv "$@"
fi

# Get kubernetes repo and deploy BT
if [ $skip_kubernetes_manifest == "false" ]; then
    get_kubernetes_repo
else
    echo "skip get kubernetes manifests"
fi

