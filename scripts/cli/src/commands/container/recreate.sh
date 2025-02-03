ignore_current_versions="${args[--ignore-current-versions]}"

export IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

if [[ ! -n "$ignore_current_versions" ]]
then
  # keep TAG and CONNECT_TAG
  export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
  export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
fi

export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
  exit 1
fi

get_environment_used
if [[ "$environment" == "ccloud" ]]
then
    get_kafka_docker_playground_dir
    DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

    if [ -f $DELTA_CONFIGS_ENV ]
    then
        source $DELTA_CONFIGS_ENV
    else
        logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
        exit 1
    fi
fi

echo "$docker_command" > /tmp/playground-command
log "💫 Recreate container(s)"
bash /tmp/playground-command

wait_container_ready