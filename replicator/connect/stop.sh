#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/stop.sh
${DIR}/../../environment/mdc-kerberos/stop.sh "${PWD}/docker-compose.kerberos.yml"