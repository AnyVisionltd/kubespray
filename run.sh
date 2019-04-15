#!/bin/bash

#arguments
function showhelp {
   echo ""
   echo "Usage examples:"
   echo "Online: $0 --inventory inventory/local/hosts.ini"
   echo "Airgap: $0 --inventory inventory/local/hosts.ini --airgap --repository 'http://192.168.20.221:8080'"
   echo ""
   echo "OPTIONS:"
   echo "  [-i|--inventory path] Ansible inventory file path."
   echo "  [-r|--repository address] APT repository address (example: http://192.168.20.221:8080), must be combined with --airgap."
   echo "  [-a|--airgap] Airgap installation mode, must be combined with --repository."
   echo "  [-h|--help] Usage message."
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
   echo "This script must be run as root"
   exit 1
fi

if [ -z "$inventory" ]; then
   echo ""
   echo "ERROR: Inventory file is not specified."
   showhelp
   exit 1
fi

# install python and pip
dpkg-query -l python python-pip python-netaddr > /dev/null 2>&1
if [ $? != 0 ]; then
  apt-get update
  apt-get install -y --no-install-recommends python python-pip python-netaddr
fi
if [ $airgap == "true" ]; then
  dpkg-query -l ansible > /dev/null 2>&1
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

# run ansible playbook
export ANSIBLE_FORCE_COLOR=True
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_PIPELINING=True

ansible-playbook -vv -i "$inventory" \
  --become --become-user=root \
  -e "$airgap_bool" \
  -e repository_address="$repository_address" \
  cluster.yml "$@"
