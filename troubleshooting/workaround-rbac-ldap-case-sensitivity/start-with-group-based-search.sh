#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


playground start-environment --environment rbac-sasl-plain


log "Creating role bindings for group"
for scope in kafka schema-registry connect ksqldb
do
    playground rbac role-binding create --principal Group:KafkaDevelopers --role SystemAdmin --scope $scope
done
