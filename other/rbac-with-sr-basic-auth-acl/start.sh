#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.4.0"
    exit 111
fi

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Creating role binding for ACL topics"
docker exec -i tools bash -c "/create-role-bindings-acl.sh"

log "Creating initial ACLs"
docker exec -i schema-registry bash -c "/tmp/create-acls.sh"
