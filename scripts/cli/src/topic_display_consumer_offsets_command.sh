ret=$(get_security_broker "--consumer.config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

log "Display content of __consumer_offsets topic, press crtl-c to stop..."
docker exec -i $container kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" $security | grep -v "_confluent-controlcenter"