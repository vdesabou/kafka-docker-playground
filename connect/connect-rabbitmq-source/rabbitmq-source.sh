#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.7.99"
then
     logwarn "minimal supported connector version is 1.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

sleep 5

log "Send message to RabbitMQ in myqueue"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

# Get the number of messages remaining in the queue
remaining_messages=$(docker exec rabbitmq rabbitmqctl -q -p "/" list_queues name messages | awk -v q="myqueue" '$1==q{print $2}')
log "Number of messages in myqueue before connector processing: $remaining_messages"

log "Creating RabbitMQ Source connector"
playground connector create-or-update --connector rabbitmq-source  << EOF
{
     "connector.class" : "io.confluent.connect.rabbitmq.RabbitMQSourceConnector",
     "tasks.max" : "1",
     "kafka.topic" : "rabbitmq",
     "rabbitmq.queue" : "myqueue",
     "rabbitmq.host" : "rabbitmq",
     "rabbitmq.username" : "myuser",
     "rabbitmq.password" : "mypassword",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF


sleep 5

log "Verify we have received the data in rabbitmq topic"
playground topic consume --topic rabbitmq --min-expected-messages 5 --timeout 60


sleep 5
log "Asserting that RabbitMQ queue is empty after connector processing"
QUEUE_NAME="myqueue"
VHOST="/"
# Get the number of messages remaining in the queue
remaining_messages=$(docker exec rabbitmq rabbitmqctl -q -p "$VHOST" list_queues name messages | awk -v q="$QUEUE_NAME" '$1==q{print $2}')

if [ -z "$remaining_messages" ]; then
logerror "failed to inspect queue $QUEUE_NAME in vhost $VHOST"
exit 1
fi

if [ "$remaining_messages" -gt 0 ]; then
logerror "queue $QUEUE_NAME still contains $remaining_messages messages, expected 0 after connector processing (all messages should be acked and removed)"
exit 1
fi

log "verified queue $QUEUE_NAME is empty - all messages were successfully consumed and deleted"

#log "Consume messages in RabbitMQ"
#docker exec -i rabbitmq_consumer bash -c "python /consumer.py myqueue"