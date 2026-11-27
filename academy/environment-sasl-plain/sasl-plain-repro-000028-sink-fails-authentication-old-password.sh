#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about SASL/PLAIN: it needs the sasl-plain environment
playground start-environment --environment sasl-plain --docker-compose-override-file "${PWD}/docker-compose.sasl-plain.repro-000028-sink-fails-authentication-old-password.yml"

playground topic produce -t payments --nb-messages 5 --forced-value '{"payment": %g}'

# the customer config: the connector reads with its own principal, "client". Its password was rotated last night
# (client-secret), the connector config still has the old one
log "Creating the FileStream sink connector"
set +e
playground connector create-or-update --connector filestream-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "payments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"client\" password=\"client-secret-2025\";"
}
EOF
set -e

sleep 10
playground connector status --connector filestream-sink || true
