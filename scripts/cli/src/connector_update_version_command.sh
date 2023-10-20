DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..


connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"

if [[ -n "$connector_tag" ]]
then
  export CONNECTOR_TAG=$connector_tag
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  export CONNECTOR_JAR=$connector_jar
fi

if [ ! -f /tmp/playground-run ]
then
  logerror "File containing run command /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

test_file=$(cat /tmp/playground-run | awk '{ print $4}')

if [ ! -f $test_file ]
then 
  logerror "File $test_file retrieved from /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

# determining the docker-compose file from from test_file
docker_compose_file=$(grep "environment" "$test_file" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | tail -n1 | xargs)
test_file_directory="$(dirname "${test_file}")"
docker_compose_file="${test_file_directory}/${docker_compose_file}"

if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
then
    logwarn "Skipping as docker-compose override file could not be detemined"
    exit 0
fi

filename=$(basename -- "$test_file")
test_file_directory="$(dirname "${test_file}")"
cd ${test_file_directory}

export DOCKER_COMPOSE_FILE_UPDATE_VERSION="$docker_compose_file"

log "✨ Loading new version(s)"
source ${DIR_CLI}/../../scripts/utils.sh

log "🎯 Now restarting connect to use new version(s)"
playground container restart --container connect