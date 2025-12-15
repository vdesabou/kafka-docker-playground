#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.7.9"
then
     logwarn "minimal supported connector version is 1.7.10 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

# remove or comment those lines if you don't need it anymore
logwarn "💪 Forcing --enable-jmx-grafana (ENABLE_JMX_GRAFANA env variable) as it was set when reproduction model was created"
export ENABLE_JMX_GRAFANA=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 100000  --nb-partitions 10  --record-size 1024 << 'EOF'
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "nested": {
        "phone": "faker.phone.imei()",
        "website": "faker.internet.domainName()"
    },
    "id": "iteration.index",
    "name": "faker.internet.userName()",
    "email": "faker.internet.exampleEmail()",
    "phone": "faker.phone.imei()",
    "website": "faker.internet.domainName()",
    "city": "faker.location.city()",
    "company": "faker.company.name()"
}
EOF

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink  << EOF
{
     "topics": "http-messages",
     "tasks.max": "10",
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
     "headers": "Content-Type: application/json"
}
EOF

sleep 10

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60

playground debug thread-dump

playground debug heap-dump

playground debug flight-recorder --container connect --action start

sleep 30

playground debug flight-recorder --container connect --action stop

playground debug generate-diagnostics --container connect

log "check consumer lag"
playground connector show-lag --connector http-sink

playground debug block-traffic --container connect --destination httpserver --port 9006 --action start

sleep 5

playground debug block-traffic --container connect --destination httpserver --port 9006 --action stop

# log "start tcp proxy with throttling to 100ms"
# playground tcp-proxy start --hostname httpserver --port 9006 --throttle-service-response 10

# log "Sending messages to topic http-messages"
# playground topic produce -t http-messages --nb-messages 100000 --record-size 1024 << 'EOF'
# {
#     "_meta": {
#         "topic": "",
#         "key": "",
#         "relationships": []
#     },
#     "nested": {
#         "phone": "faker.phone.imei()",
#         "website": "faker.internet.domainName()"
#     },
#     "id": "iteration.index",
#     "name": "faker.internet.userName()",
#     "email": "faker.internet.exampleEmail()",
#     "phone": "faker.phone.imei()",
#     "website": "faker.internet.domainName()",
#     "city": "faker.location.city()",
#     "company": "faker.company.name()"
# }
# EOF

# log "check consumer lag"
# playground connector show-lag --connector http-sink

log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
log "📛 Pyroscope is reachable at http://127.0.0.1:4040"
log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password)"