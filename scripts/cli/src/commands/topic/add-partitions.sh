topic="${args[--topic]}"
nb_partitions="${args[--nb-partitions]}"
verbose="${args[--verbose]}"

get_security_broker "--command-config"
get_environment_used

set +e
existing_topics=$(playground get-topic-list)
set -e
if ! echo "$existing_topics" | grep -qFx "$topic"
then
    logerror "❌ topic $topic does not exist (create it with: playground topic create --topic $topic --nb-partitions $nb_partitions)"
    exit 1
fi

# kafka-topics --describe | --alter, in the broker container (or pod, or a CP image for Confluent Cloud)
function run_kafka_topics () {
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
        get_connect_image
        docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-topics "$@" --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
    elif [[ "$environment" == cfk* ]]
    then
        kubectl -n confluent exec $container -- kafka-topics "$@" --topic $topic --bootstrap-server $bootstrap_server $security
    else
        docker exec $container kafka-topics "$@" --topic $topic --bootstrap-server $bootstrap_server $security
    fi
}

current=$(run_kafka_topics --describe 2>/dev/null | grep -o 'PartitionCount: *[0-9]*' | head -1 | grep -o '[0-9]*$')
if [ -z "$current" ]
then
    logerror "❌ could not get the number of partitions of topic $topic"
    exit 1
fi
if [ "$nb_partitions" -le "$current" ]
then
    logerror "❌ topic $topic already has $current partition(s): a topic can only grow (Kafka never removes partitions), give more than $current"
    exit 1
fi

if [[ -n "$verbose" ]]
then
    log "🐞 CLI command used"
    echo "kafka-topics --alter --partitions $nb_partitions --topic $topic"
fi
log "➕ Adding partitions to topic $topic: $current → $nb_partitions"
run_kafka_topics --alter --partitions "$nb_partitions"
log "✅ topic $topic has $nb_partitions partitions"
log "⚠️ records with a key: hash(key) % $nb_partitions now decides their partition, new records of a key can land in another partition than the older ones"
