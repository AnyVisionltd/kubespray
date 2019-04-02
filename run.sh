#!/bin/bash

#arguments
function showhelp {
   echo ""
   echo "Online example: ./run.sh"
   echo "Airgap example: ./run.sh --airgap --repository-address 'http://192.168.20.221:8080'"
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
        -r|--repository-address)
        shift
        repository_address=${1}
        shift
        continue
        ;;
        -a|--airgap)
        shift
        airgap="true"
        airgap_bool='{airgap: True}'
        continue
        ;;
    esac
    break
done

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
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
    apt-get install -y --no-install-recommends ansible
  fi
else
  pip freeze | grep -i ansible > /dev/null 2>&1
  if [ $? != 0 ]; then
    pip install -r requirements.txt
  fi
fi

# run ansible playbook
ansible-playbook -vv -i inventory/sample/hosts.ini \
  --become --become-user=root \
  -e "$airgap_bool" \
  -e repository_address="$repository_address" \
  cluster.yml "$@"

echo -e "\n\n"
echo 'Done!'
echo -e "\n"
