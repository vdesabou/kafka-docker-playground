ignore_current_versions="${args[--ignore-current-versions]}"
eval "fresh_volumes_array=(${args[--fresh-volumes]})"

get_environment_used
if [[ "$environment" == cfk* ]]
then
    logerror "❌ container recreate is not supported in cfk mode"
    exit 1
fi
if [[ "$environment" == ansible* ]]
then
    logerror "❌ container recreate is not supported in ansible mode: a recreated host loses what the playbook installed, run the playbook again instead"
    log "    playground ansible playbook (playground ansible inventory set <path> <value> to change a variable first)"
    exit 1
fi

export IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

if [[ ! -n "$ignore_current_versions" ]]
then
  # keep TAG and CP_CONNECT_TAG
  export_running_cp_tags
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

# --fresh-volumes: docker compose up reuses the anonymous volumes of a container it recreates, so its data folder (and
# the meta.properties of a KRaft node: node id, cluster id) survives a recreate. Removing the container with its
# anonymous volumes (docker rm -v) makes up create it again with empty ones
for fresh_container in "${fresh_volumes_array[@]}"
do
    if ! docker inspect "$fresh_container" > /dev/null 2>&1
    then
        logerror "❌ container $fresh_container does not exist (playground get-container-list)"
        exit 1
    fi
    fresh_volumes=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Destination}} {{end}}{{end}}' "$fresh_container" 2>/dev/null)
    log "🧽 removing container $fresh_container and its anonymous volumes (${fresh_volumes% }): it starts with empty data folders"
    docker rm -f -v "$fresh_container" > /dev/null
done

# recreate replays the compose definition without the values of 'container set-environment-variables': forget them,
# so that the next set-environment-variables does not bring them back
clear_env_overrides

echo "$docker_command" > /tmp/playground-command
log "💫 Recreate container(s)"
bash /tmp/playground-command

wait_container_ready

test_file=$(get_current_test_file) || exit 1

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
        if version_gt $TAG_BASE "7.9.99"
        then
            playground container exec --root --command "microdnf -y install libnsl2"
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.3 /usr/lib64/libnsl.so.1"
        else
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.2 /usr/lib64/libnsl.so.1"
        fi
    fi
fi