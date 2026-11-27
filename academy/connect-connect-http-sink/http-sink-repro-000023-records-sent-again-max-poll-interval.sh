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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000023-records-sent-again-max-poll-interval.yml"

# the issue: the API got slower (2 seconds per request) after a release on its side
playground tools http-server set-response --delay 2000

log "Sending 30 orders to topic http-messages"
playground topic produce -t http-messages --nb-messages 30 --forced-value '{"order": %g}'

# the customer config: one record per request, and a max.poll.interval.ms lowered to "detect stuck tasks faster"
log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
{
     "topics": "http-messages",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "http.api.url": "http://httpserver:9006",
     "batch.max.size": "1",
     "consumer.override.max.poll.interval.ms": "20000"
}
EOF

log "Waiting 2 minutes: 30 records, 2 seconds each"
sleep 120

playground connector status --connector http-sink
playground connector show-lag --connector http-sink --once || true
