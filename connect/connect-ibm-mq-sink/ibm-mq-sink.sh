#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

echo "Creating IBM MQ source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
                    "topics": "sink-messages",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink/config | jq .

sleep 5

echo "Verify message received in DEV.QUEUE.1 queue"
docker exec ibmmq bash -c "/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1"

