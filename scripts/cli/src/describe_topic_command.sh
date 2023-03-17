topic="${args[--topic]}"

log "Description of topic $topic"
docker exec broker kafka-topics --describe --topic $topic --bootstrap-server broker:9092