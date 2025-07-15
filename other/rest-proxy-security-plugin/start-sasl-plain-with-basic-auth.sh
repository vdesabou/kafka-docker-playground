#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROPERTIES_CONFIG_FILE="/etc/kafka/sasl-plain-with-basic-auth.properties"
if version_gt $TAG_BASE "7.9.9"; then
  export PROPERTIES_CONFIG_FILE="/etc/kafka/sasl-plain-with-basic-auth-8-plus.properties"
fi

playground start-environment --environment sasl-plain --docker-compose-override-file "${PWD}/docker-compose.sasl-plain.yml"

# run as root for linux case where key is owned by root user
log "HTTP client using clientrestproxy principal"
docker exec --privileged --user root restproxy curl -X POST -u clientrestproxy:clientrestproxy-secret -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "http://localhost:8086/topics/jsontest"
