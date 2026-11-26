#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.7.9"
then
     logwarn "minimal supported connector version is 1.7.10 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000014-http-sink-400-and-dlq.yml"

# the issue: a new validation rule of the API refuses the records (400 Bad Request)
playground tools http-server set-response --status-code 400
playground tools http-server set-response << 'EOF'
{"error":"email: must be a company address"}
EOF

log "Sending 3 messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 3 << 'EOF'
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "id": "iteration.index",
    "name": "faker.internet.userName()",
    "email": "faker.internet.exampleEmail()"
}
EOF

# the customer config: "errors.tolerance all and a dead letter queue: a bad record can't stop the connector"
log "Creating http-sink connector"
playground connector create-or-update --connector http-sink --no-wait << EOF
{
     "topics": "http-messages",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":"false",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "reporter.result.topic.value.format": "string",
     "http.api.url": "http://httpserver:9006",
     "request.body.format" : "json",
     "headers": "Content-Type: application/json",
     "max.retries": "3",
     "retry.backoff.ms": "1000",
     "errors.tolerance": "all",
     "errors.deadletterqueue.topic.name": "dlq",
     "errors.deadletterqueue.topic.replication.factor": "1",
     "errors.deadletterqueue.context.headers.enable": "true"
}
EOF

sleep 30

log "The connector:"
playground connector status --connector http-sink
