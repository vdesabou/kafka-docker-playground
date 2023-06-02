#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

log "Creating ActiveMQ sink connector"
playground connector create-or-update --connector active-mq-sink << EOF
{
               "connector.class": "io.confluent.connect.jms.ActiveMqSinkConnector",
               "topics": "sink-messages",
               "activemq.url": "tcp://activemq:61616",
               "activemq.username": "admin",
               "activemq.password": "admin",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5

log "Get messages from DEV.QUEUE.1 JMS queue:"
curl -XGET -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is my message" /tmp/result.log

