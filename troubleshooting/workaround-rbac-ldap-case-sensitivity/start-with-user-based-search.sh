#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cp $PWD/10_alice.ldif ../../environment/rbac-sasl-plain/scripts/security/ldap_users/10_alice.ldif

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.user-based-search.yml"


log "Creating role bindings for group"
for scope in kafka schema-registry connect ksqldb
do
    playground rbac role-binding create --principal Group:KafkaDevelopers --role SystemAdmin --scope $scope
done
