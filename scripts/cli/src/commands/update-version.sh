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
  if [[ $tag == *"@"* ]]
  then
    tag=$(echo "$tag" | cut -d "@" -f 2)
  fi
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

test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

# determining the docker-compose file from from test_file
docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
test_file_directory="$(dirname "${test_file}")"
docker_compose_file="${test_file_directory}/${docker_compose_file}"

if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
then
    logwarn "Skipping as docker-compose override file could not be detemined"
    exit 0
fi

if [[ -n "$connector_tag" ]]
then
  if [ "$connector_tag" == " " ]
  then
    connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
    if [ "$connector_paths" == "" ]
    then
        logwarn "❌ skipping as it is not an example with connector"
        exit 1
    else
        connector_tags=""
        for connector_path in ${connector_paths//,/ }
        do
          full_connector_name=$(basename "$connector_path")
          owner=$(echo "$full_connector_name" | cut -d'-' -f1)
          name=$(echo "$full_connector_name" | cut -d'-' -f2-)

          if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
          then
            # happens when plugin is not coming from confluent hub
            logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
          fi

          ret=$(choose_connector_tag "$owner/$name")
          connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
          
          if [ -z "$connector_tags" ]; then
            connector_tags="$connector_tag"
          else
            connector_tags="$connector_tags,$connector_tag"
          fi
        done

        connector_tag="$connector_tags"
    fi
  fi

  flag_list="$flag_list --connector-tag=$connector_tag"
  export CONNECTOR_TAG="$connector_tag"
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

test_file_directory="$(dirname "${test_file}")"
cd ${test_file_directory}

export DOCKER_COMPOSE_FILE_UPDATE_VERSION="$docker_compose_file"

if [ "$flag_list" != "" ]
then
  log "✨ Loading new version(s) based on flags ⛳ $flag_list"
else
  log "✨ Loading new version(s) without any flags ⛳"
fi

if [ $tag_changed -eq 1 ]
then
    log "💣 Detected confluent version change, restarting containers"
    playground container recreate --ignore-current-versions
else
    # in case there is a change in docker-compose...
    playground container recreate
fi

if [[ -n "$connector_tag" ]] || [[ -n "$connector_zip" ]] || [[ -n "$connector_jar" ]]
then
    if [ $tag_changed -eq 0 ]
    then
        log "🧩 a connector flag is set: restarting connect container to make sure new version(s) are used"
        playground container restart --container connect
    fi
    sleep 5

    $root_folder/scripts/wait-for-connect-and-controlcenter.sh

    sleep 10

    playground connector versions
else
    sleep 4

    $root_folder/scripts/wait-for-connect-and-controlcenter.sh
fi