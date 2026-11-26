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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000013-tasks-max-one-task-works.yml"

# the API takes 500 ms per request: one request at a time handles 2 records per second
playground tools http-server set-response --status-code 200 --delay 500
playground tools http-server set-response << 'EOF'
{"message":"Hello, World!"}
EOF

# the topic was created with the default of the cluster: 1 partition
playground topic create --topic orders

# the customer config: "4 tasks, so 4 requests in parallel"
log "Creating http-sink connector with tasks.max 4"
playground connector create-or-update --connector http-sink << EOF
{
     "topics": "orders",
     "tasks.max": "4",
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
     "batch.max.size": "1"
}
EOF

# the issue: the shop sends 6 orders per second
log "Sending 6 orders per second to topic orders (the key is the order id), in the background"
playground topic produce -t orders --key "order%g" --rate 6 --duration 1800 --background << 'EOF'
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "id": "iteration.index",
    "product": "faker.commerce.productName()",
    "quantity": "faker.number.int({ min: 1, max: 5 })"
}
EOF

# a sink commits its offsets every 60 seconds (offset.flush.interval.ms)
sleep 75

log "The lag of the connector:"
playground connector show-lag --connector http-sink --once
