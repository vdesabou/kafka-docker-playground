#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/ldap-authorizer-sasl-plain/start.sh "${PWD}/docker-compose.ldap-authorizer-sasl-plain.ldap-failover.yml"

