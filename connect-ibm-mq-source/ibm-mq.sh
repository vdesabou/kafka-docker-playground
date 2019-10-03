#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../nosecurity/start.sh

echo "Creating IBM MQ source connector"
docker-compose exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "ibm-mq-source",
               "config": {
                    "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
                    "kafka.topic": "MyKafkaTopicName",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Sending messages to DEV.QUEUE.1 JMS queue:"
docker container exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

sleep 5

echo "Verify we have received the data in MyKafkaTopicName topic"
docker-compose exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic MyKafkaTopicName --from-beginning --max-messages 2
