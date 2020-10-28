#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"
if [ ! -z "$TRAVIS" ]
then
     # if this is travis build, use private image.
     export ORACLE_IMAGE="vdesabou/oracle12"
fi

${DIR}/../../environment/plaintext/stop.sh "${PWD}/docker-compose.plaintext-cdb-table.yml"
${DIR}/../../environment/plaintext/stop.sh "${PWD}/docker-compose.plaintext-pdb-table.yml"