#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/stop.sh "${PWD}/docker-compose.replicator.plaintext.yml"
${DIR}/../../environment/mdc-plaintext/stop.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../../environment/mdc-sasl-plain/stop.sh "${PWD}/docker-compose.sasl-plain.yml"
${DIR}/../../environment/mdc-kerberos/stop.sh "${PWD}/docker-compose.kerberos.yml"