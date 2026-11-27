#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about SASL/OAUTHBEARER (OAuth client_credentials with Keycloak): it needs the sasl-oauthbearer
# environment
playground start-environment --environment sasl-oauthbearer --docker-compose-override-file "${PWD}/docker-compose.sasl-oauthbearer.repro-000032-sink-cannot-get-token-rotated-secret.yml"

playground topic produce -t shipments --nb-messages 5 --forced-value '{"shipment": %g}'

# the customer config: the connector logs in with its own OAuth client, "client". Its secret was rotated in the
# identity provider last week, the connector config still has the old one
log "Creating the FileStream sink connector, with its own OAuth client"
set +e
playground connector create-or-update --connector shipments-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "shipments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId=\"client\" clientSecret=\"client-secret-2025\";"
}
EOF
set -e

sleep 10
playground connector status --connector shipments-sink || true
