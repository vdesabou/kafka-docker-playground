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

    test_folder=$(grep ":${dir}:" $template_file | cut -d "(" -f 2 | cut -d ")" -f 1)
    travis="❌"
    if [ "$test_folder" != "" ]
    then
      set +e
      grep "$test_folder" .travis.yml | grep -v jar > /dev/null
      if [ $? = 0 ]
      then
        travis="✅"
      fi
      set -e
    fi

    if [ "$dir" = "kafka-connect-couchbase" ]
    then
        sed -e "s|:${dir}:|3.4.8 \| Open Source (Couchbase) \| \| $travis |g" \
            $readme_file > $readme_tmp_file
    else
        version=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.version')

        license=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.license[0].name')

        owner=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.owner.name')

        release_date=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.release_date')
        if [ "$release_date" = "null" ]
        then
          release_date=""
        fi

        if [ "$license" = "Confluent Software Evaluation License" ]
        then
          type="Confluent Subscription"
        elif [ "$license" = "Apache License 2.0" ] || [ "$license" = "Apache 2.0" ] || [ "$license" = "Apache License, Version 2.0" ] || [ "$license" = "The Apache License, Version 2.0" ]
        then
          type="Open Source ($owner)"
        else
          type="$license"
        fi

        sed -e "s|:${dir}:|${version} \| $type \| $release_date \| $travis |g" \
            $readme_file > $readme_tmp_file
    fi
    cp $readme_tmp_file $readme_file
done