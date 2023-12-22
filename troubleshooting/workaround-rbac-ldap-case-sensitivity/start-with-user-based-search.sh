#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cp $PWD/create-role-bindings-for-group.sh ../../environment/rbac-sasl-plain/scripts/helper/
cp $PWD/10_alice.ldif ../../environment/rbac-sasl-plain/scripts/security/ldap_users/10_alice.ldif

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.user-based-search.yml"


log "Creating role bindings for group"
docker exec -i tools bash -c "/tmp/helper/create-role-bindings-for-group.sh"
