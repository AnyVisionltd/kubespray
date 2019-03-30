#!/bin/bash

#arguments
function showhelp {
   echo ""
   echo "Online example: ./run.sh"
   echo "Airgap example: ./run.sh --airgap --repository-address 'http://192.168.20.221:8080'"
}

## Defaults
airgap='{airgap: False}'

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
        airgap='{airgap: True}'
        continue
        ;;
    esac
    break
done

# add aptly repo to sources.list
grep -i "$repository_address" /etc/apt/sources.list > /dev/null 2>&1
if [ $? != 0 ]; then
  mkdir -p /etc/apt-orig
  rsync -a --ignore-existing /etc/apt/ /etc/apt-orig/
  rm -rf /etc/apt/sources.list.d/*
  echo "deb [arch=amd64 trusted=yes] $repository_address bionic main" > /etc/apt/sources.list
fi

# install ansible and pip
dpkg-query -l python ansible python-pip python-netaddr > /dev/null 2>&1
if [ $? != 0 ]; then
  apt-get update
  apt-get install -y --no-install-recommends python ansible python-pip python-netaddr
fi

# run ansible playbook
sudo ansible-playbook -vv -i inventory/sample/hosts.ini \
  --become --become-user=root \
  -e "$airgap" \
  -e repository_address="$repository_address" \
  cluster.yml "$@"

echo 'Done!'
