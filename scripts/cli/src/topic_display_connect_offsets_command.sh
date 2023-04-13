environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

security_broker=""
if [ "$environment" != "plaintext" ]
then
    security_broker="--consumer.config /etc/kafka/secrets/client_without_interceptors.config"
fi

log "Display content of connect offsets topic, press crtl-c to stop..."
docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --property print.timestamp=true $security_broker