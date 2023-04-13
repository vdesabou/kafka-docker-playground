topic="${args[--topic]}"

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

security_broker=""
if [ "$environment" != "plaintext" ]
then
    security_broker="--command-config /etc/kafka/secrets/client_without_interceptors.config"
fi

log "Describing topic $topic"
docker exec broker kafka-topics --describe --topic $topic --bootstrap-server broker:9092 $security_broker