#!/bin/bash

# The script must rn with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo permissions"
   #exec sudo $0 "$@"
   echo "exit"
   exit 1
fi

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

DEFAULT_IPV4=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')

#arguments
function showhelp {
   echo ""
   echo "Usage examples:"
   echo "Online: $0 --inventory $BASEDIR/inventory/local/hosts.ini --key < gcr.io token (string) or json key file path > "
   echo "Airgap: $0 --inventory $BASEDIR/inventory/local/hosts.ini --airgap --repository http://[[ LOCAL_APT_REPO_IP_ADDRESS ]]:8085/"
   echo "Metallb: $0 --inventory $BASEDIR/inventory/local/hosts.ini --metallb-range '10.5.0.50-10.5.0.99'"
   echo ""
   echo "OPTIONS:"
   #echo "  [-i|--inventory path] Ansible inventory file path (default: $BASEDIR/inventory/local/hosts.ini)"
   #echo "  [-r|--repository address] Manually specify APT repository address (default: default route ipv4 address)"
   #echo "  [-a|--airgap] Airgap installation mode (default: false)"
   #echo "  [--metallb-range] Deploy MetalLB layer 2 load-balancer and specify its IP range (default: false)"
   echo "  [--skip-kubespray] Skip Kubespray playbook (default: false)"
   #echo "  [-h|--help] Display this usage message"
   #echo "  [-k|--key] Provide a gcr.io registry token key (string) or json key file (json file path)"
   #echo "  [--skip-kubernetes-manifest] Skip deploy kubernetes manifests (default: false)"
   #echo "  [--deploy-app] deploy app better tommorow (default: false)"
   echo "  [--download-only-kubernetes-manifest] Skip deploy kubernetes manifests (default: false)"
   echo "  [-v|--version] Provide version for kubernetes manifests repository"
   echo ""
}


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

update_invenotry_file(){
    echo "update hostname ${HOSTNAME} in invetoryfile ${BASEDIR}/inventory/local/hosts.ini"
    sed -i "s/node1/${HOSTNAME}/g" ${BASEDIR}/inventory/local/hosts.ini
}

get_kubernetes_repo(){
    k8s_manifests_dir="/opt/kubernetes"    
    kubernetes_ver=${kubernetes_version:-1.22.0}

    # KEY Screen
    tokenkey=$(whiptail --title "Installation Wizard" --inputbox "Insert registry token key or json key file path" 10 100 3>&1 1>&2 2>&3)
    #exitstatus=$?
    if [[ ${tokenkey:-} == "" ]]; then
        echo "You chose Cancel. Will exit..."
        exit 0
    fi

    #if kubernetes maniferst already exist and not empty dir
    image_name=gcr.io/${gcr_account:-anyvision-production}/kubernetes:${kubernetes_ver}
    if [ -d ${k8s_manifests_dir}/${kubernetes_ver} ] && [ "$(ls -A ${k8s_manifests_dir}/${kubernetes_ver})" ] ; then
        echo "the kubernetes dir ${k8s_manifests_dir}/${kubernetes_ver} is already exist. skipping get kubernetes repo..."
    elif [ $airgap == "true" ] ; then
        echo "airgap mode is on. skip docker login.."
        id=$(docker create $image_name)
        mkdir -p ${k8s_manifests_dir}/${kubernetes_ver}
        docker cp $id:/kubernetes/. ${k8s_manifests_dir}/${kubernetes_ver}
        docker rm -v $id        
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
    if [ $download_only_kubernetes_manifest == "false" ]; then
        deploy_app
    fi
}

deploy_app(){

    arguments=""

    if [ ${INSTALL_TYPE} == "UPGRADE"] &&  [ ${PRODUCT_TYPE} == "BT"]; then
        arguments+=" --better_tomorrow"
    fi

    if [ ${PRODUCT_TYPE} == "BT"]; then
        arguments+=" --better_tomorrow"
    fi

    echo "deploy app"
    #cd ${k8s_manifests_dir}/${kubernetes_ver}/templates/
    if [ $airgap == "true" ] ; then
        ${k8s_manifests_dir}/${kubernetes_ver}/templates/deployer.sh -b
    else
        ${k8s_manifests_dir}/${kubernetes_ver}/templates/deployer.sh -k "${tokenkey}" -b
    fi
}


## Defaults
#airgap="false"
#airgap_bool='{airgap: False}'
metallb="false"
#skip_kubespray="false"
#skip_kubernetes_manifest="false"
#deployapp="false"
download_only_kubernetes_manifest="false"




## whiptail menue

# Install Type Screen
INSTALL_TYPE=$(whiptail --title "Installation Wizard" --menu "Choose your option:" 15 100 4 \
"FRESH" "installation" \
"UPGRADE" "installation" 3>&1 1>&2 2>&3)
#exitstatus=$?
if [[ ${INSTALL_TYPE:-} == "" ]]; then
    echo "You chose Cancel. Will exit..."
    exit 0
fi


# Product Type Screen
#PRODUCT_TYPE=""
PRODUCT_TYPE=$(whiptail --title "Installation Wizard" --menu "Choose your option:" 15 100 4 \
"BT" "Install" \
"HQ" "Install" 3>&1 1>&2 2>&3)
#exitstatus=$?
if [[ ${PRODUCT_TYPE:-} == "" ]]; then
    echo "You chose Cancel. Will exit..."
    exit 0
fi

# Data migration MODE Screen
if [[ ${INSTALL_TYPE:-} == "UPGRADE" ]]; then
    DATA_MIGRATION_TYPE=$(whiptail --title "Installation Wizard" --checklist \
    "Choose the data migration type:" 15 100 4 \
    "MONGO" "upgrade mongo data base" ON \
    "OBJECT_STORAGE" "migrate files from file system to object storage" OFF \
    "TA" "migrate files form track archive file system to the data base" OFF 3>&1 1>&2 2>&3)
    #exitstatus=$?
    if [[ ${DATA_MIGRATION_TYPE:-} = "" ]]; then
        echo "You chose Cancel. Will exit..."
        exit 0
    fi
    DATA_MIGRATION_TYPE_LIST=$(echo $DATA_MIGRATION_TYPE | tr -d '"' | tr " " "\n")
fi

# Version Screen
VERSION=$(whiptail --title "Installation Wizard" --menu "Choose your option:" 15 100 4 \
"1.22.0" "Version" \
"1.22.3" "Version" 3>&1 1>&2 2>&3)
#exitstatus=$?
if [[ ${VERSION:-} == "" ]]; then
    echo "You chose Cancel. Will exit..."
    exit 0
fi

# method (online/offline) Screen
INSTALL_METHOD=$(whiptail --title "Installation Wizard" --menu "Choose your option:" 15 100 4 \
"ONLINE" "Perform online installation" \
"OFFLINE" "Perform offline installation (must have all relevant packages in the USB stick)" 3>&1 1>&2 2>&3)
#exitstatus=$?
if [[ ${INSTALL_METHOD:-} == "" ]]; then
    echo "You chose Cancel. Will exit..."
    exit 0
fi

if [[ ${INSTALL_METHOD:-} == "ONLINE" ]]; then
    airgap_bool='{airgap: False}'
    airgap="false"
else
    airgap_bool='{airgap: True}'
    airgap="true"
fi

if [[ ${INSTALL_METHOD:-} == "OFFLINE" ]]; then
    # repository_address Screen
    host_default_ip="$(hostname -i)"
    repository_address=""
    repository_address=$(whiptail --title "Installation Wizard" --inputbox "Insert repository ip address :" "http://<ip>:8085/" 10 100 3>&1 1>&2 2>&3)
    #exitstatus=$?
    if [[ ${repository_address:-} == "" ]]; then
        echo "You chose Cancel. Will exit..."
        exit 0
    fi
fi

# Install MODE Screen
INSTALL_MODES=$(whiptail --title "Installation Wizard" --checklist \
"Choose installation mode:" 15 100 4 \
"ENVIRONMENT" "Install packages and configure the Kubernetes (kubespray)" ON \
"APP" "Install App" ON 3>&1 1>&2 2>&3)
    #exitstatus=$?
    if [[ ${INSTALL_MODES:-} == "" ]]; then
    echo "You chose Cancel. Will exit..."
    exit 0
fi

INSTALL_MODES_LIST=$(echo $INSTALL_MODES | tr -d '"' | tr " " "\n")

skip_kubespray="true"
deployapp="false"
while IFS='' read -r installMode || [ -n "$installMode" ]; do
    if [ $installMode == "ENVIRONMENT" ]; then
        skip_kubespray="false"
    elif [ $installMode == "APP" ]; then
        deployapp="true"
    fi
done <<< "${INSTALL_MODES_LIST}"

# Cluster mode Screen
CLUSTER_MODE=$(whiptail --title "Installation Wizard" --menu "Choose your option:" 15 100 4 \
"AIO" "Install locally (All In One)" \
"CLUSTER" "Install on more then 1 node (need to edit inventory file)" 3>&1 1>&2 2>&3)
#exitstatus=$?
if [[ ${CLUSTER_MODE:-} == "" ]]; then
    echo "You chose Cancel. Will exit..."
    exit 0
fi

if [ ${CLUSTER_MODE} == "AIO" ]; then

    if [ -z "$inventory" ] && ( [ $skip_kubespray == "false" ] || [ $metallb == "true" ] ) ; then
        echo ""
        echo "info: Inventory file is not specified. will use the default $BASEDIR/inventory/local/hosts.ini"
        inventory="${BASEDIR}/inventory/local/hosts.ini"
        #showhelp
        #exit 1
    fi

    #rename hostname in the invtoryfile
    if [[ $inventory == *"local/hosts.ini"* ]]; then
        update_invenotry_file
    fi

else
    # inventory file Screen
    inventory=""
    inventory=$(whiptail --title "Installation Wizard" --inputbox "Insert inventory file path:" "${BASEDIR}/inventory/sample/inventory.ini" 10 100 3>&1 1>&2 2>&3)
    #exitstatus=$?
    if [ ${inventory} == "" ]; then
        echo "You chose Cancel. Will exit..."
        exit 0
    fi
fi



## Deploy
# POSITIONAL=()
# while [[ $# -gt 0 ]]; do
#     key="$1"
#     case $key in
#         -h|help|--help)
#         showhelp
#         exit 0
#         ;;
#         -r|--repository)
#         shift
#         repository_address="$1"
#         shift
#         continue
#         ;;
#         -a|--airgap)
#         shift
#         airgap="true"
#         airgap_bool='{airgap: True}'
#         continue
#         ;;
#         -m|--metallb-range)
#         shift
#         metallb="true"
#         metallb_vars="{'metallb':{'ip_range':'$1','limits':{'cpu':'100m','memory':'100Mi'},'port':'7472','version':'v0.7.3'}}"
#         shift
#         continue
#         ;;
#         -v|--version|--version)
#         shift
#         kubernetes_version="$1"
#         shift
#         continue
#         ;;
#         -k|key|--key)
#         shift
#         tokenkey="$1"
#         shift
#         continue
#         ;;
#         skip-kubespray|--skip-kubespray)
#         shift
#         skip_kubespray="true"
#         continue
#         ;;
#         deploy-app|--deploy-app)
#         shift
#         deployapp="true"
#         continue
#         ;;
#         download-only-kubernetes-manifest|--download-only-kubernetes-manifest)
#         shift
#         download_only_kubernetes_manifest="true"
#         continue
#         ;;  
#         -i|--inventory)
#         shift
#         inventory="$1"
#         shift
#         continue
#         ;;
#     esac
#     break
# done




# if [ $deployapp == "true" ] && [ -z "$tokenkey" ] && [ "$airgap" == "false" ]; then
#    echo "ERROR: GCR key is not specified"
#    showhelp
#    exit 1
# fi

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
	if [ $? -eq 0 ]; then
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
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sudo yum install -y python-pip git yum pciutils ansible

	for package in \
		python \
		python-pip \
		python-netaddr \
		sshpass \
	; do
		yum list installed "$package" > /dev/null 2>&1
	        if [ $? -eq 0 ]; then
		   set -e
		   yum install -q -y $package > /dev/null
		   set +e
		fi
	done
fi

# install ansible
set -e
pip install --quiet --no-index --find-links $BASEDIR/pip_deps/ setuptools
pip install --quiet --no-index --find-links $BASEDIR/pip_deps/ -r $BASEDIR/requirements.txt
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
    set -e
    ansible-playbook -i "$inventory" \
      --become --become-user=root \
      -e "$airgap_bool" \
      -e repository_address="$repository_address" \
      $BASEDIR/cluster.yml -vv "$@"
    set +e
else
    echo "skip kubespray"
fi

# if [ $metallb == "true" ]; then
#     echo "deploy metallb"
#     ansible-playbook -i "$inventory" \
#       --become --become-user=root \
#       -e "$metallb_vars" \
#       $BASEDIR/contrib/metallb/metallb.yml -vv "$@"
# fi

# Get kubernetes repo and deploy BT
#if [ $skip_kubernetes_manifest == "false" ]; then





if [ $deployapp == "true" ]; then
    get_kubernetes_repo
else
    echo "skip get kubernetes manifests"
fi

