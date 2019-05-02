#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

DEFAULT_IPV4=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')

#arguments
function showhelp {
   echo ""
   echo "Usage examples:"
   echo "$0 --inventory inventory/local/hosts.ini"
   echo ""
   echo "OPTIONS:"
   echo "  [-i|--inventory path] Ansible inventory file path (required)"
   echo "  [-h|--help] Display this usage message"
   echo ""
}

## Defaults

## Deploy
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|help|--help)
        showhelp
        exit 0
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

echo ""
echo "====================================================="
echo "================ reset cluster procedure ============"
echo "====================================================="

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

read -r -p "Are you sure you want to reset cluster state? its irreversible but possible. Type 'yes' to reset your cluster.[y/N]: " response
case "$response" in
    [yY][eE][sS]|[yY]) 
        # run ansible playbook
        export ANSIBLE_FORCE_COLOR=True
        export ANSIBLE_HOST_KEY_CHECKING=False
        export ANSIBLE_PIPELINING=True
     
         ansible-playbook -vv -i "$inventory" \
         --become --become-user=root \
         $BASEDIR/reset.yml
        ;;
    *)
        echo "No Worries There is always another time"
        exit 0;
        ;;
esac
