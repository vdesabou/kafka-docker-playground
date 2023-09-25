#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f "${PWD}/docker-compose.rbac-with-azure-ad.yml" down -v --remove-orphans