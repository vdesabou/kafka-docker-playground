ignore_current_versions="${args[--ignore-current-versions]}"

export IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

if [[ ! -n "$ignore_current_versions" ]]
then
  # keep TAG and CP_CONNECT_TAG
  export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
  export CP_CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
fi

export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
  exit 1
fi

enable_flink=$(playground state get flags.ENABLE_FLINK)
if [ "$enable_flink" != "1" ]
then
  export flink_connectors=""
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
        logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
        exit 1
    fi
fi

echo "$docker_command" > /tmp/playground-command
log "💫 Recreate container(s)"
bash /tmp/playground-command

wait_container_ready

test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

if [[ "${test_file}" == *"xstream"* ]]
then
    log "💫 xstream test detected, re-installing libraries..."
    # https://github.com/confluentinc/common-docker/pull/743 and https://github.com/adoptium/adoptium-support/issues/1285
    set +e
    playground container exec --root --command "sed -i "s/packages\.adoptium\.net/adoptium\.jfrog\.io/g" /etc/yum.repos.d/adoptium.repo"
    playground container exec --root --command "microdnf -y install libaio"

    if [ "$(uname -m)" = "arm64" ]
    then
        :
    else
        if version_gt $TAG_BASE "7.9.9"
        then
            playground container exec --root --command "microdnf -y install libnsl2"
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.3 /usr/lib64/libnsl.so.1"
        else
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.2 /usr/lib64/libnsl.so.1"
        fi
    fi
fi