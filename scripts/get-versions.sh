#!/bin/bash

set -e

function log() {
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
  echo -e "$YELLOW`date +"%H:%M:%S"` $@$NC"
}

function logerror() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "$RED`date +"%H:%M:%S"` $@$NC"
}

function logwarn() {
  PURPLE='\033[0;35m'
  NC='\033[0m' # No Color
  echo -e "$PURPLE`date +"%H:%M:%S"` $@$NC"
}


image_version=$1
template_file=README-template.md
readme_file=README.md
readme_tmp_file=/tmp/README.md

cp $template_file $readme_file

for dir in $(docker run vdesabou/kafka-docker-playground-connect:${image_version} ls /usr/share/confluent-hub-components/)
do
    log "processing $dir"
    if [ "$dir" = "kafka-connect-couchbase" ]
    then
        sed -e "s|:${dir}:|3.4.8|g" \
            $readme_file > $readme_tmp_file
    else
        version=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.version')

        sed -e "s|:${dir}:|${version}|g" \
            $readme_file > $readme_tmp_file
    fi
    cp $readme_tmp_file $readme_file
done