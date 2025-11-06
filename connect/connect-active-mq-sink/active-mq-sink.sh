#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.1.15"
then
     logwarn "minimal supported connector version is 2.1.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 1 << 'EOF'
This is my message
EOF

log "Creating ActiveMQ sink connector"
playground connector create-or-update --connector active-mq-sink  << EOF
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
curl -XGET -u admin:admin http://localhost:8161/api/message/DEV.QUEUE.1?type=queue > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is my message" /tmp/result.log

