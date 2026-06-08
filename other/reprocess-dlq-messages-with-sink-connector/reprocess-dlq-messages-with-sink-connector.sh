#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic avro-topic"
playground topic produce -t avro-topic --nb-messages 10 < ../../scripts/cli/predefined-schemas/avro/lead.avsc

log "killing schema-registry container to have the messages sent to DLQ since schema-registry is not available"
playground container kill --container schema-registry

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink  << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "avro-topic",
    "file": "/tmp/output.json",

    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq",
    "errors.deadletterqueue.topic.replication.factor": "1",
    "errors.deadletterqueue.context.headers.enable": "true",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 5

playground connector show-lag --connector filestream-sink --max-wait 120

log "Restart schema-registry container to make the DLQ messages available"
playground container restart --container schema-registry

sleep 5

log "Set alias for subject avro-topic with alias dlq-value"
playground schema set-alias --subject avro-topic-value --alias dlq-value


log "Creating DLQ FileStream Sink connector, reading from DLQ topic using alias and writing to a file"
playground connector create-or-update --connector dlq-filestream-sink  << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "dlq",
    "file": "/tmp/output.json",

    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq2",
    "errors.deadletterqueue.topic.replication.factor": "1",
    "errors.deadletterqueue.context.headers.enable": "true",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 3

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json