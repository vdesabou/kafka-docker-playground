topic="${args[--topic]}"
nb_partitions="${args[--nb-partitions]}"
verbose="${args[--verbose]}"

get_security_broker "--command-config"
get_environment_used

set +e
existing_topics=$(playground get-topic-list)
if ! echo "$existing_topics" | grep -qFx "$topic"
then
    set -e
    log "🆕 Creating topic $topic"
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
            echo "kafka-topics --create --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --partitions $nb_partitions ${other_args[*]}"
        fi
        get_connect_image
        docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-topics --create --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --partitions $nb_partitions ${other_args[*]}
    else
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "kafka-topics --create --topic $topic --bootstrap-server $bootstrap_server --partitions $nb_partitions $security ${other_args[*]}"
        fi
        docker exec $container kafka-topics --create --topic $topic --bootstrap-server $bootstrap_server --partitions $nb_partitions $security ${other_args[*]}
    fi
else
    logerror "❌ topic $topic already exist !"
    exit 1
fi