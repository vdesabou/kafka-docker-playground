topic="${args[--topic]}"

ret=$(get_security_broker "--command-config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

log "Describing topic $topic"
docker exec $container kafka-topics --describe --topic $topic --bootstrap-server broker:9092 $security