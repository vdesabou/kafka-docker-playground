#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

sleep 5

log "Send message to RabbitMQ in myqueue"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.rabbitmq \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.rabbitmq.client \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'

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
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rabbitmq --from-beginning  --property print.headers=true --max-messages 5

#log "Consume messages in RabbitMQ"
#docker exec -i rabbitmq_consumer bash -c "python /consumer.py myqueue"
exit 0

[
  {
    "topic": "rabbitmq",
    "partition": 0,
    "offset": 0,
    "timestamp": 1675344193025,
    "timestampType": "CREATE_TIME",
    "headers": [
      {
        "key": "rabbitmq.consumer.tag",
        "stringValue": "amq.ctag-5D78I_dTbfbdbEELwkPaFQ"
      },
      {
        "key": "rabbitmq.content.type",
        "stringValue": "application/json"
      },
      {
        "key": "rabbitmq.content.encoding",
        "stringValue": "utf-8"
      },
      {
        "key": "rabbitmq.delivery.mode",
        "stringValue": "1"
      },
      {
        "key": "rabbitmq.priority",
        "stringValue": "1"
      },
      {
        "key": "rabbitmq.correlation.id",
        "stringValue": null
      },
      {
        "key": "rabbitmq.reply.to",
        "stringValue": null
      },
      {
        "key": "rabbitmq.expiration",
        "stringValue": null
      },
      {
        "key": "rabbitmq.message.id",
        "stringValue": "0"
      },
      {
        "key": "rabbitmq.timestamp",
        "stringValue": null
      },
      {
        "key": "rabbitmq.type",
        "stringValue": null
      },
      {
        "key": "rabbitmq.user.id",
        "stringValue": null
      },
      {
        "key": "rabbitmq.app.id",
        "stringValue": null
      },
      {
        "key": "rabbitmq.delivery.tag",
        "stringValue": "1"
      },
      {
        "key": "rabbitmq.redeliver",
        "stringValue": "false"
      },
      {
        "key": "rabbitmq.exchange",
        "stringValue": ""
      },
      {
        "key": "rabbitmq.routing.key",
        "stringValue": "myqueue"
      }
    ],
    "key": "0",
    "value": "\u0000\u0000\u0000\u0000\u0001{\"id\": 0, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}",
    "__confluent_index": 0
  }
]


container="rabbitmq"
ip=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep $container | cut -d " " -f 3)
log "Block incoming traffic from $container (ip=$ip)"
docker exec --privileged --user root connect bash -c "iptables -D INPUT -p tcp -s 192.168.48.4 -j DROP"
