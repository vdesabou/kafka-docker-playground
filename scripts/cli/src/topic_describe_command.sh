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
    log "🔎 Describing topic $topic"
    docker exec $container kafka-topics --describe --topic $topic --bootstrap-server broker:9092 $security
done