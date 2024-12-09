#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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