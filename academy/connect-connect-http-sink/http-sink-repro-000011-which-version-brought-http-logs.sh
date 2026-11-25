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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000011-which-version-brought-http-logs.yml"

playground tools http-server set-response --status-code 200

log "Sending 3 messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 3 --value '{"id": %g, "name": "name-%g"}'

# the customer: "we set TRACE on org.apache.http to see the requests of the HTTP sink, and nothing shows up"
playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
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
     "http.api.url": "http://httpserver:9006",
     "request.body.format" : "json",
     "headers": "Content-Type: application/json"
}
EOF

sleep 20

log "The 3 requests reached the server:"
playground tools http-server requests --last 3

# the problem is reproduced when the logs of connect have no line of the HttpClient wire log
playground repro assert --reproduced-if-command "! docker logs connect 2>&1 | grep -q 'http-outgoing-'"
