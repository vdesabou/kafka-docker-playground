#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "2.1.15"
then
     logwarn "minimal supported connector version is 2.1.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

cd ../../connect/connect-jms-active-mq-sink
if [ ! -f ${DIR}/activemq-all-5.15.4.jar ]
then
     log "Downloading activemq-all-5.15.4.jar"
     wget -q https://repo1.maven.org/maven2/org/apache/activemq/activemq-all/5.15.4/activemq-all-5.15.4.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 1 << 'EOF'
This is my message
EOF

log "Creating JMS ActiveMQ sink connector"
playground connector create-or-update --connector jms-active-mq-sink  << EOF
{
     "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
     "topics": "sink-messages",
     "java.naming.factory.initial": "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
     "java.naming.provider.url": "tcp://activemq:61616",
     "java.naming.security.principal": "admin",
     "java.naming.security.credentials": "admin",
     "connection.factory.name": "ConnectionFactory",
     "jms.destination.type": "queue",
     "jms.destination.name": "DEV.QUEUE.1",
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
