if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

log "Display content of __consumer_offsets topic, press crtl-c to stop..."
if [ "$environment" != "plaintext" ]
then
    docker exec -i broker bash -c 'kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" --consumer.config /etc/kafka/secrets/client_without_interceptors.config | grep -v "_confluent-controlcenter"'
else
    docker exec -i broker bash -c 'kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" | grep -v "_confluent-controlcenter"'
fi