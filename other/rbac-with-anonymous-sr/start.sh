#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.4.0"
    exit 111
fi

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Creating role bindings for ANONYMOUS"
docker exec -i tools bash -c "/create-role-bindings-anonymous.sh"
