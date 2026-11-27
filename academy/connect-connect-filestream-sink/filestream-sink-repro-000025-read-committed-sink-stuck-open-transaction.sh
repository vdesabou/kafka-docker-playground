#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000025-read-committed-sink-stuck-open-transaction.yml"

# 💥 a transactional producer of the payments service crashed in the middle of a transaction, and its new instance
# uses another transactional.id: nobody will ever end the transaction of the old one (until its timeout, 15 minutes)
log "The payments service writes 10 payments in a transaction, then crashes"
playground topic produce -t payments --nb-messages 10 --forced-value '{"payment": %g, "batch": "crashed"}' --transactional-id payments-service-1 --transaction open --transaction-timeout 900000

log "Its new instance writes 5 payments, committed"
playground topic produce -t payments --nb-messages 5 --forced-value '{"payment": %g, "batch": "new"}' --transactional-id payments-service-2

# the customer config: read_committed, "to never write a payment that was rolled back"
log "Creating the FileStream sink connector"
playground connector create-or-update --connector filestream-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "payments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.isolation.level": "read_committed"
}
EOF

sleep 20

log "What the connector wrote"
playground container exec -c connect --command "cat /tmp/output.json" || true
playground connector show-lag --connector filestream-sink --once || true
