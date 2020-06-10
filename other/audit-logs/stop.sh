#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/rbac-sasl-plain/stop.sh "${PWD}/docker-compose-rbac-sasl-plain.yml"
${DIR}/../../environment/sasl-plain/stop.sh "${PWD}/docker-compose-sasl-plain.yml"