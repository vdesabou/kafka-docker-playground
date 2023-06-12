topic="${args[--topic]}"
nb_partitions="${args[--nb-partitions]}"

ret=$(get_security_broker "--command-config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

log "🆕 Creating topic $topic"
if [[ "$environment" == "environment" ]]
then
    if [ -f /tmp/delta_configs/env.delta ]
    then
        source /tmp/delta_configs/env.delta
    else
        logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
        exit 1
    fi
    if [ ! -f /tmp/delta_configs/ak-tools-ccloud.delta ]
    then
        logerror "ERROR: /tmp/delta_configs/ak-tools-ccloud.delta has not been generated"
        exit 1
    fi

    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
    dir1=$(echo ${DIR_CLI%/*})
    root_folder=$(echo ${dir1%/*})
    IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
    source $root_folder/scripts/utils.sh

    docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --create --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --partitions $nb_partitions ${other_args[*]}
else
    docker exec $container kafka-topics --create --topic $topic --bootstrap-server broker:9092 --partitions $nb_partitions $security ${other_args[*]}
fi