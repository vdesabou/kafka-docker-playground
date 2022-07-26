#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ${DIR}/docker-compose.plaintext.yml down -v --remove-orphans