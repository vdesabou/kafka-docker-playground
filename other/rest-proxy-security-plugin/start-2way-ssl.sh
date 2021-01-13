#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/2way-ssl/start.sh "${PWD}/docker-compose.2way-ssl.yml"


log "HTTP client using clientrestproxy principal"
curl -X POST --cert ../../environment/2way-ssl/security/clientrestproxy.certificate.pem --key ../../environment/2way-ssl/security/clientrestproxy.key --tlsv1.2 --cacert ../../environment/2way-ssl/security/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://localhost:8086/topics/jsontest"

log "Verify principal clientrestproxy is used"
docker container logs broker | grep Write | grep jsontest
