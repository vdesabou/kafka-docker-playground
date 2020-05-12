#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml"

log "HTTP client using clientrestproxy principal"
docker exec restproxy curl -X POST --cert /etc/kafka/secrets/clientrestproxy.certificate.pem --key /etc/kafka/secrets/clientrestproxy.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://localhost:8086/topics/jsontest"

log "Verify principal clientrestproxy is used"
docker container logs broker | grep Write | grep jsontest