#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

OLDIFS="$IFS"
IFS=$'\n' # bash specific
for image in $(grep -h "image:\s.*\/.*" $(find ${DIR}/../connect -name "*.yml"))
do
  image=$(echo $image | tr -s " " | cut -d " " -f 3)

    # check for scripts containing "repro"
  if [[ "$image" == *"\${"* ]]; then
      continue
  fi
  if [[ "$image" == "home" ]]; then
      continue
  fi
  echo "$image" >> /tmp/list.txt
done
IFS="$OLDIFS"

OLDIFS="$IFS"
IFS=$'\n' # bash specific
for image in $(cat /tmp/list.txt | uniq)
do
  log "pulling image $image"
  docker pull $image
done
IFS="$OLDIFS"

