#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.1.5"
then
     logwarn "minimal supported connector version is 1.1.6 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

mkdir -p ../../connect/connect-splunk-source/security
cd ../../connect/connect-splunk-source/security
playground tools certs-create --output-folder "$PWD" --container splunk
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Splunk source connector"
playground connector create-or-update --connector splunk-source  << EOF
{
     "connector.class": "io.confluent.connect.SplunkHttpSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "splunk-source",
     "splunk.collector.index.default": "default-index",
     "splunk.port": "8889",
     "splunk.ssl.key.store.path": "/tmp/kafka.splunk.keystore.jks",
     "splunk.ssl.key.store.password": "confluent",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Simulate an application sending data to the connector"
curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'

sleep 5

log "Verifying topic splunk-source"
playground topic consume --topic splunk-source --min-expected-messages 1 --timeout 60