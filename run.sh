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

# run ansible playbook
sudo ansible-playbook -vv -i inventory/sample/hosts.ini \
  --become --become-user=root \
  -e "$airgap" \
  -e repository_address="$repository_address" \
  cluster.yml "$@"

echo -e "\n\n"
echo 'Done!'
echo -e "\n"
