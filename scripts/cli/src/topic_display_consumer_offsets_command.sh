get_security_broker "--consumer.config"
get_environment_used

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

log "Display content of __consumer_offsets topic, press crtl-c to stop..."
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

    docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --describe --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
else
    docker exec -i $container kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" $security | grep -v "_confluent-controlcenter"
fi