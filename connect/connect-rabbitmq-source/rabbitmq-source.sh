#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.7.99"
then
     logwarn "minimal supported connector version is 1.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

sleep 5

log "Send message to RabbitMQ in myqueue"
playground container exec --container rabbitmq-producer --command "bash -c \"python /producer.py myqueue 5\""

playground mq wait --container rabbitmq --queue myqueue --min-expected-messages 5

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

log "Asserting that RabbitMQ queue is empty after connector processing (all messages acked and removed)"
playground mq wait --container rabbitmq --queue myqueue --max-expected-messages 0 --max-wait 60

#log "Consume messages in RabbitMQ"
#playground container exec -i rabbitmq-consumer bash -c "python /consumer.py myqueue"