#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" -f "${PWD}/docker-compose.add-connect-worker.yml" down -v