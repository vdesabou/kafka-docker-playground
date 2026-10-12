#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "Audit logs is only available from Confluent Platform 5.4.0"
    exit 111
fi

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Creating role bindings for ANONYMOUS"
playground rbac role-binding create --principal User:ANONYMOUS --role ResourceOwner --resource "Subject:*"

# raw curl on purpose: 'playground schema' authenticates, the point here is to call schema-registry without credentials
log "Registering a schema without credentials (User:ANONYMOUS)"
for i in $(seq 1 12)
do
    # the role binding takes a few seconds to reach schema-registry
    if curl --fail -s http://localhost:8081/subjects/anonymous-value/versions -H "Content-Type: application/vnd.schemaregistry.v1+json" -d '{"schema":"{\"type\":\"string\"}"}'
    then
        echo
        break
    fi
    if [ $i -eq 12 ]
    then
        logerror "❌ anonymous request to schema-registry failed"
        exit 1
    fi
    sleep 5
done

log "Listing subjects without credentials"
curl --fail -s http://localhost:8081/subjects | grep "anonymous-value"
