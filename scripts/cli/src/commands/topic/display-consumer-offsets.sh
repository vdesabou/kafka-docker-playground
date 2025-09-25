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
        echo "kafka-console-consumer --bootstrap-server $bootstrap_server --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" $security"
    fi

	tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-server-.*:' | awk -F':' '{print $2}')
	if [ $? != 0 ] || [ "$tag" == "" ]
	then
		logerror "Could not find current CP version from docker ps"
		exit 1
	fi

	formatter="kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter"
	if version_gt $tag "7.9.9"; then
		formatter="org.apache.kafka.tools.consumer.OffsetsMessageFormatter"
	fi

    docker exec -i $container kafka-console-consumer --bootstrap-server $bootstrap_server --topic __consumer_offsets --from-beginning --formatter "$formatter" $security | grep -v "_confluent-controlcenter"
fi