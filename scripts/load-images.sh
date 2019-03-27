#!/bin/bash
images="bt-images.tar.gz"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -r|--registry)
        reg="$2"
        shift # past argument
        shift # past value
        continue
        ;;
        -i|--images)
        images="$2"
        shift # past argument
        shift # past value
        continue
        ;;
        -h|--help)
        help="true"
        shift
        continue
        ;;
    esac
    break
done

usage () {
    echo "USAGE: $0 [--images bt-images.tar.gz] [--registry my.registry.com:5000]"
    echo "  [-i|--images path] tar.gz generated by docker save."
    echo "  [-r|--registry registry:port] target private registry:port."
    echo "  [-h|--help] Usage message"
}

if [[ $help ]]; then
    usage
    exit 0
fi

set -e

## Load images to local docker daemon
echo ""
echo "#######################################################"
echo "###         Loading images, please wait..."
echo "#######################################################"
echo ""
images_array=()
while IFS= read -r line; do
    echo $line
    if [[ $line =~ "Loaded image" ]]; then
        image=${line#"Loaded image: "}
        images_array+=( "$image" )
    fi
done < <( docker load --input $images )
echo ""

## Check if the user has specified a registry, if not - try to use the one specified in app_images.env
if [[ -z $reg ]]; then
    if [[ -n $LOCAL_REGISTRY_PREFIX ]]; then
        $reg=${LOCAL_REGISTRY_PREFIX%/}   ## remove "/" suffix
    fi
fi

## If we have a registry, tag and push
if [[ -n $reg ]]; then
  echo "#######################################################"
  echo "###   Tagging images and pushing, please wait..."
  echo "#######################################################"
  echo ""
    for i in ${images_array[@]}; do
        echo "Tagging: $i  >>>  $reg/$i"
        docker tag $i $reg/$i
        docker push $reg/$i
        echo ""
    done
fi

echo "#######################################################"
echo ""
echo "                         Done!"
echo ""
