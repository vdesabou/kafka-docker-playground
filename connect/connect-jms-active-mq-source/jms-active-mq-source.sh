#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jms-active-mq-source
if [ ! -f ${DIR}/activemq-all-5.15.4.jar ]
then
     log "Downloading activemq-all-5.15.4.jar"
     wget -q https://repo1.maven.org/maven2/org/apache/activemq/activemq-all/5.15.4/activemq-all-5.15.4.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Creating JMS ActiveMQ source connector"
playground connector create-or-update --connector jms-active-mq-source  << EOF
{
     "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "MyKafkaTopicName",
     "java.naming.factory.initial": "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
     "java.naming.provider.url": "tcp://activemq:61616",
     "java.naming.security.principal": "admin",
     "java.naming.security.credentials": "admin",
     "connection.factory.name": "ConnectionFactory",
     "jms.destination.name": "DEV.QUEUE.1",
     "jms.destination.type": "queue",
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


