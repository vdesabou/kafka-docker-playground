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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000008-http-sink-timeouts-slow-network.yml"

log "The API answers 200 right away"
playground tools http-server set-response --status-code 200
playground tools http-server set-response << 'EOF'
{"message":"Hello, World!"}
EOF

# the issue: the network between the worker and the API got slow (a VPN, a proxy, a saturated link): 1.5 s of latency
playground debug degrade-traffic --container httpserver --destination connect --latency 1500ms --action start

log "Sending 10 messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
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

# the customer config: the API usually answers in a few milliseconds, so 1 second looked like plenty
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
     "http.request.timeout.ms": "1000",
     "max.retries": "2",
     "retry.backoff.ms": "1000"
}
EOF

sleep 30

log "The connector:"
playground connector status --connector http-sink
