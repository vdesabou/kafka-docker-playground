#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "12.1.99"
then
     logwarn "minimal supported connector version is 12.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

cd ../../connect/connect-jms-active-mq-source
if [ ! -f ${DIR}/activemq-all-5.15.4.jar ]
then
     log "Downloading activemq-all-5.15.4.jar"
     wget -q https://repo1.maven.org/maven2/org/apache/activemq/activemq-all/5.15.4/activemq-all-5.15.4.jar
fi
cd -


cd ../../connect/connect-jms-active-mq-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jms/lib/
cp ../../connect/connect-jms-active-mq-source/activemq-all-5.15.4.jar ../../confluent-hub/confluentinc-kafka-connect-jms/lib/activemq-all-5.15.4.jar
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

sleep 5

log "Asserting that ActiveMQ queue DEV.QUEUE.1 is empty after connector processing"
log "This tests that commitRecord API properly deletes messages from external system"
QUEUE_SIZE=$(curl -s -u admin:admin "http://localhost:8161/admin/xml/queues.jsp" | grep -A 5 "DEV.QUEUE.1" | grep "size" | sed 's/.*size=\"\([0-9]*\)\".*/\1/')

if [ -z "$QUEUE_SIZE" ]; then
    logerror "❌ Failed to retrieve queue size from ActiveMQ"
    exit 1
fi

log "Current queue size for DEV.QUEUE.1: $QUEUE_SIZE"

if [ "$QUEUE_SIZE" -eq 0 ]; then
    log "✅ SUCCESS: ActiveMQ queue DEV.QUEUE.1 is empty - message was successfully consumed and deleted"
else
    logerror "❌ FAILURE: Messages still remain in ActiveMQ queue DEV.QUEUE.1 (size: $QUEUE_SIZE) - message was not deleted"
    log "Displaying queue statistics:"
    curl -s -u admin:admin "http://localhost:8161/admin/xml/queues.jsp" | grep -A 10 "DEV.QUEUE.1"
    exit 1
fi
