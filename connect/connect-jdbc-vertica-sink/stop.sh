#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/stop.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../../environment/plaintext/stop.sh "${PWD}/docker-compose.plaintext-repro-tombstone.yml"