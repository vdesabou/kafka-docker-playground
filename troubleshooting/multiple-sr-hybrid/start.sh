#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

log "Executing curl -i http://localhost:1500/v1/metadata/schemaRegistryUrls"
curl -i http://localhost:1500/v1/metadata/schemaRegistryUrls