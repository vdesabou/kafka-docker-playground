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

items=($topic)
for topic in ${items[@]}
do
    log "💯 Get number of records in a topic $topic"
    docker exec $container kafka-run-class kafka.tools.GetOffsetShell --broker-list broker:9092 $security --topic $topic --time -1 | awk -F ":" '{sum += $3} END {print sum}'
done