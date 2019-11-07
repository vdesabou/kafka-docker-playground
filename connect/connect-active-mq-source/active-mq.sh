#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Creating ActiveMQ source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "active-mq-source",
               "config": {
                    "connector.class": "io.confluent.connect.activemq.ActiveMQSourceConnector",
                    "kafka.topic": "MyKafkaTopicName",
                    "activemq.url": "tcp://activemq:61616",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Sending messages to DEV.QUEUE.1 JMS queue:"
curl -XPOST -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue

sleep 5

echo "Verify we have received the data in MyKafkaTopicName topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic MyKafkaTopicName --from-beginning --max-messages 1
