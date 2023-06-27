#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL using rmohr/activemq:5.15.9 image"
docker run -u0 --rm -v $PWD:/tmp rmohr/activemq:5.15.9 bash -c "/tmp/certs-create.sh && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
cd ${DIR}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mtls.yml"


log "Creating ActiveMQ source connector"
playground connector create-or-update --connector active-mq-source-mtls << EOF
{
     "connector.class": "io.confluent.connect.activemq.ActiveMQSourceConnector",
     "kafka.topic": "MyKafkaTopicName",
     "activemq.url": "ssl://activemq:61617",
     "jms.destination.name": "DEV.QUEUE.1",
     "jms.destination.type": "queue",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
curl -XPOST -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 1 --timeout 60
