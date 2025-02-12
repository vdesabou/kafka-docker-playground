topic="${args[--topic]}"
verbose="${args[--verbose]}"

get_security_broker "--command-config"

if [[ ! -n "$topic" ]]
then
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-connect-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

get_environment_used

items=($topic)
for topic in ${items[@]}
do
    log "🔎 Describing topic $topic"
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
        if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
        then
            logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
            exit 1
        fi
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "kafka-topics --describe --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties"
        fi
        get_connect_image
        docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --describe --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
    else
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "kafka-topics --describe --topic $topic --bootstrap-server $bootstrap_server:9092 $security"
        fi
        docker exec $container kafka-topics --describe --topic $topic --bootstrap-server $bootstrap_server:9092 $security
    fi
done