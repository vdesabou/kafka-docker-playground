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
    log "💯 Get number of records in topic $topic"
    set +e
    playground topic describe --topic $topic > /tmp/result.log 2>/tmp/result.log
    grep "does not exist" /tmp/result.log > /dev/null 2>&1
    if [ $? == 0 ]
    then
        logwarn "topic $topic does not exist !"
        continue
    fi
    set +e
    if [[ "$environment" == "environment" ]]
    then
        if [ ! -f /tmp/delta_configs/librdkafka.delta ]
        then
            logerror "ERROR: /tmp/delta_configs/librdkafka.delta has not been generated"
            exit 1
        fi
        tr -d '"' < /tmp/delta_configs/librdkafka.delta > /tmp/delta_configs/librdkafka_no_quotes_tmp.delta
        grep -v "basic.auth.user.info" /tmp/delta_configs/librdkafka_no_quotes_tmp.delta > /tmp/delta_configs/librdkafka_no_quotes.delta
        docker run -i --network=host \
                -v /tmp/delta_configs/librdkafka_no_quotes.delta:/tmp/configuration/ccloud.properties \
            confluentinc/cp-kcat:latest kcat \
                -F /tmp/configuration/ccloud.properties \
                -C -t $topic \
                -e -q > /tmp/result.log 2>/dev/null
        wc -l /tmp/result.log | awk '{print $1}'
    else
        if ! version_gt $TAG_BASE "6.9.9" && [ "$security" != "" ]
        then
            # GetOffsetShell does not support security before 7.x
            ret=$(get_security_broker "--consumer.config")
            container=$(echo "$ret" | cut -d "@" -f 1)
            security=$(echo "$ret" | cut -d "@" -f 2)
            set +e
            docker exec $container kafka-console-consumer --bootstrap-server broker:9092 --topic $topic $security --from-beginning --timeout-ms 15000 2>/dev/null | wc -l | tr -d ' '
            set -e
        else
            docker exec $container kafka-run-class kafka.tools.GetOffsetShell --broker-list broker:9092 $security --topic $topic --time -1 | awk -F ":" '{sum += $3} END {print sum}'
        fi
    fi
done