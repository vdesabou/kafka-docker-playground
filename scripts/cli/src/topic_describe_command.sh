topic="${args[--topic]}"

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

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

items=($topic)
for topic in ${items[@]}
do
    log "🔎 Describing topic $topic"
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

        docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --describe --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
    else
        docker exec $container kafka-topics --describe --topic $topic --bootstrap-server broker:9092 $security
    fi
done