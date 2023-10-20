DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"

tag_changed=0
flag_list=""
if [[ -n "$tag" ]]
then
  current_tag=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)

  if [ "$current_tag" == "" ]
  then
    logerror "❌ Could not retrieve current cp version (--tag or TAG) being used"
    exit 1
  fi
  
  if [ "$current_tag" == "$tag" ]
  then
    logwarn "--tag=$tag is same as current tag, ignoring..."
  else
    tag_changed=1
    flag_list="--tag=$tag"
  fi

  export TAG=$tag
fi

if [[ -n "$connector_tag" ]]
then
  flag_list="$flag_list --connector-tag=$connector_tag"
  export CONNECTOR_TAG=$connector_tag
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-zip=$connector_zip"
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-jar=$connector_jar"
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

test_file_directory="$(dirname "${test_file}")"
cd ${test_file_directory}

export DOCKER_COMPOSE_FILE_UPDATE_VERSION="$docker_compose_file"

log "✨ Loading new version(s) based on flags ⛳ $flag_list"
if [ $tag_changed -eq 1 ]
then
    log "💣 Detected confluent version change, restarting containers"
    playground container recreate --ignore-current-versions
else
    playground container recreate
fi

if [[ -n "$connector_tag" ]] || [[ -n "$connector_zip" ]] || [[ -n "$connector_jar" ]]
then
    if [ $tag_changed -eq 0 ]
    then
        log "🧨 Detected connector version change(s), restarting connect container to make sure new version(s) are used"
        playground container restart --container connect
    fi
    sleep 4

    $root_folder/scripts/wait-for-connect-and-controlcenter.sh

    sleep 8

    playground connector versions
else
    sleep 4

    $root_folder/scripts/wait-for-connect-and-controlcenter.sh
fi