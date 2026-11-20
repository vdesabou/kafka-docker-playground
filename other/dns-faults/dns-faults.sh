#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
if [[ "$PLAYGROUND_ENVIRONMENT" == cfk* ]]
then
    logwarn "playground debug dns is not supported with cfk yet"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.7.9"
then
    logwarn "minimal supported connector version is 1.7.10 for CP 8.0"
    exit 111
fi

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground tools http-server set-response --status-code 200

log "Step 1: an http sink delivers 10 records to httpserver"
playground topic produce -t http-messages --nb-messages 10 --value '{"id": %g}'
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
    "reporter.result.topic.value.format": "string",
    "http.api.url": "http://httpserver:9006"
}
EOF
playground tools http-server requests --min-expected-requests 10 --max-wait 120

log "Step 2: httpserver no longer resolves from connect (NXDOMAIN)"
playground debug dns --container connect --host httpserver --nxdomain
# the JVM keeps a resolved name for 30 seconds (networkaddress.cache.ttl), and the http client reuses its
# connections: new records are needed, after the cache expired, to see the failure
sleep 35
playground topic produce -t http-messages --nb-messages 10 --value '{"id": %g}'
# the http sink does not retry an UnknownHostException (max.retries is for the http errors): the task fails at once
playground connector wait --connector http-sink --state FAILED --max-wait 180
playground container logs --container connect --wait-for-log "UnknownHostException" --max-wait 60
playground debug dns --container connect --host httpserver

log "Step 3: back to the real DNS: the task stays FAILED until it is restarted, then delivers the 10 records"
playground debug dns --container connect --reset
# the JVM keeps a failed lookup for 10 seconds (networkaddress.cache.negative.ttl)
sleep 15
playground connector restart --connector http-sink
playground connector wait --connector http-sink --max-wait 120
playground tools http-server requests --min-expected-requests 20 --max-wait 180
