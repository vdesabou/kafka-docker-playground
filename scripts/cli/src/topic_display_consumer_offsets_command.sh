get_security_broker "--consumer.config"
get_environment_used
verbose="${args[--verbose]}"



log "Display content of __consumer_offsets topic, press crtl-c to stop..."
if [[ "$environment" == "ccloud" ]]
then
    logerror " __consumer_offsets topic is not readable in cloud"
    exit 1
else

    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" $security"
    fi
    docker exec -i $container kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" $security | grep -v "_confluent-controlcenter"
fi