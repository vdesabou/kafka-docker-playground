#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Send message to RabbitMQ in myqueue"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

log "Creating RabbitMQ Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.rabbitmq.RabbitMQSourceConnector",
               "tasks.max" : "1",
               "kafka.topic" : "rabbitmq",
               "rabbitmq.queue" : "myqueue",
               "rabbitmq.host" : "rabbitmq",
               "rabbitmq.username" : "myuser",
               "rabbitmq.password" : "mypassword",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/rabbitmq-source/config | jq .


sleep 5

log "Verify we have received the data in rabbitmq topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rabbitmq --from-beginning --max-messages 5

#log "Consume messages in RabbitMQ"
#docker exec -it rabbitmq_consumer bash -c "python /consumer.py myqueue"