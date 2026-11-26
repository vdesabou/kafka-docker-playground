#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "12.1.99"
then
     logwarn "minimal supported connector version is 12.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating ActiveMQ source connector"
playground connector create-or-update --connector active-mq-source  << EOF
{
     "connector.class": "io.confluent.connect.activemq.ActiveMQSourceConnector",
     "kafka.topic": "MyKafkaTopicName",
     "activemq.url": "tcp://activemq:61616",
     "jms.destination.name": "DEV.QUEUE.1",
     "jms.destination.type": "queue",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
playground mq put --container activemq --queue DEV.QUEUE.1 --message message

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 1 --timeout 60

sleep 5

log "Stopping the connector to force unacknowledged messages to be redelivered"
playground connector stop --connector active-mq-source

sleep 5

log "Asserting that ActiveMQ queue DEV.QUEUE.1 is empty after connector processing (commitRecord deletes the messages)"
playground mq wait --container activemq --queue DEV.QUEUE.1 --max-expected-messages 0 --max-wait 60

