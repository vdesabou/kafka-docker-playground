#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000024-new-sink-skips-existing-records.yml"

log "The orders of yesterday, already in the topic"
playground topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "day": "yesterday"}'

# the customer config: copied from a connector that "must not replay old data after a reset"
log "Creating the new FileStream sink connector"
playground connector create-or-update --connector filestream-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "orders",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.auto.offset.reset": "latest"
}
EOF

sleep 10

log "The orders of today"
playground topic produce -t orders --nb-messages 3 --forced-value '{"order": %g, "day": "today"}'

sleep 10

log "What the connector wrote"
playground container exec -c connect --command "cat /tmp/output.json"
