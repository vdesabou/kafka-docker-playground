#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about RBAC (Confluent Server authorizer, MDS, LDAP users): it needs the rbac-sasl-plain environment
playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.repro-000031-sink-not-authorized-own-service-account.yml"

playground topic produce -t invoices --nb-messages 5 --forced-value '{"invoice": %g}'

# the customer config: the security team wants one service account per connector, appSA for this one (on RBAC, the
# clients of a connector authenticate as principal.service.name), "it has the same rights as connectorSA": it has
# none, nobody created its role bindings
log "Creating the FileStream sink connector, running as appSA"
set +e
playground connector create-or-update --connector invoices-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "invoices",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "principal.service.name": "appSA",
     "principal.service.password": "appSA"
}
EOF
set -e

sleep 10
playground connector status --connector invoices-sink || true
