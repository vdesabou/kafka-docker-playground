#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

test_file="$PWD/$1"
comments="$2"

if [ "$test_file" = "" ]
then
  logerror "ERROR: test_file is not provided as argument!"
  exit 1
fi

if [ ! -f "$test_file" ]
then
  logerror "ERROR: test_file $test_file does not exist!"
  exit 1
fi

if [[ "$test_file" != *".sh" ]]
then
  logerror "ERROR: test_file $test_file is not a .sh file!"
  exit 1
fi

if [ "$comments" = "" ]
then
  logerror "ERROR: comments is not provided as argument!"
  exit 1
fi

test_file_directory="$(dirname "${test_file}")"

# determining the connector from test_file
docker_compose_file=$(grep "environment" "$test_file" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
comments_kebab_case="${comments// /-}"

if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
then
  filename=$(basename -- "$test_file")
  extension="${filename##*.}"
  filename="${filename%.*}"

  repro_test_file="$test_file_directory/$filename-repro-$comments_kebab_case.$extension"

  filename=$(basename -- "$PWD/$docker_compose_file")
  extension="${filename##*.}"
  filename="${filename%.*}"

  docker_compose_test_file="$test_file_directory/$filename.repro-$comments_kebab_case.$extension"
  log "Creating $docker_compose_test_file"
  cp $PWD/$docker_compose_file $docker_compose_test_file

  docker_compose_test_file_name=$(basename -- "$docker_compose_test_file")

  log "Creating $repro_test_file"
  sed -e "s|$docker_compose_file|$docker_compose_test_file_name|g" \
      $test_file > $repro_test_file

else
  logerror "📁 Could not determine docker-compose override file from $test_file !"
  exit 1
fi