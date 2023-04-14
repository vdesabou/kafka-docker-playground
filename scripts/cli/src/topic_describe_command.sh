topic="${args[--topic]}"

security_broker=$(get_security_broker)

log "Describing topic $topic"
docker exec broker kafka-topics --describe --topic $topic --bootstrap-server broker:9092 $security_broker