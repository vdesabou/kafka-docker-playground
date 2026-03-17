topic_pattern="${args[--topic]}"
verbose="${args[--verbose]}"
skip_delete_schema="${args[--skip-delete-schema]}"

get_security_broker "--command-config"
get_environment_used

set +e
existing_topics=$(playground get-topic-list)
if echo "$existing_topics" | grep -qFx -- "$topic_pattern"; then
    topics_to_delete="$topic_pattern"
else
    regex_pattern="^(${topic_pattern})$"
    topics_to_delete=$(echo "$existing_topics" | grep -E -- "$regex_pattern")
    grep_status=$?

    if [ $grep_status -eq 2 ]; then
        logerror "❌ Invalid regex provided for --topic: $topic_pattern"
        exit 1
    fi

    if [ $grep_status -ne 0 ] || [ -z "$topics_to_delete" ]; then
        log "❌ topic $topic_pattern does not exist and regex does not match any topic !"
        exit 0
    fi

    log "✨ --topic is treated as regex. Matching topics:"
    echo "$topics_to_delete"
fi
set -e

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
fi

if [[ -n "$skip_delete_schema" ]]
then
    log "🔰 Do not delete subject/schema as --skip-delete-schema is set"
fi

items=($topics_to_delete)
for topic in "${items[@]}"
do
    log "❌ Deleting topic $topic"

    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        if [[ "$environment" == "ccloud" ]]
        then
            echo "kafka-topics --delete --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties"
        else
            echo "kafka-topics --delete --topic $topic --bootstrap-server $bootstrap_server $security"
        fi
    fi

    if [[ "$environment" == "ccloud" ]]
    then
        get_connect_image
        docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-topics --delete --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
    else
        docker exec $container kafka-topics --delete --topic $topic --bootstrap-server $bootstrap_server $security
    fi

    if [[ -z "$skip_delete_schema" ]]
    then
        if playground schema get --subject "$topic-key" > /dev/null 2>&1
        then
            log "🔰 Delete subject $topic-key"
            playground schema delete --subject "$topic-key" --permanent
        fi

        if playground schema get --subject "$topic-value" > /dev/null 2>&1
        then
            log "🔰 Delete subject $topic-value"
            playground schema delete --subject "$topic-value" --permanent
        fi
    fi
done