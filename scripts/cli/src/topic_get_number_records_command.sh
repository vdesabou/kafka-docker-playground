topic="${args[--topic]}"

ret=$(get_security_broker "--command-config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

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

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

items=($topic)
for topic in ${items[@]}
do
    log "💯 Get number of records in a topic $topic"
    if [[ "$environment" == "environment" ]]
    then
        if [ ! -f /tmp/delta_configs/librdkafka.delta ]
        then
            logerror "ERROR: /tmp/delta_configs/librdkafka.delta has not been generated"
            exit 1
        fi
        docker run -i --network=host \
            -v /tmp/delta_configs/librdkafka.delta:/tmp/configuration/ccloud.properties \
            confluentinc/cp-kcat:latest kcat \
                -F /tmp/configuration/ccloud.properties \
                -C -t $topic \
                -e -q \
                | grep -v "Reading configuration from file" | wc -l | tr -d ' '
    else
        docker exec $container kafka-run-class kafka.tools.GetOffsetShell --broker-list broker:9092 $security --topic $topic --time -1 | awk -F ":" '{sum += $3} END {print sum}'
    fi
done