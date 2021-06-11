#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --broker-list localhost:9092 --topic sales_US

log "Starting replicator instances"
docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f docker-compose.mdc-plaintext.replicator.yml up -d

../../scripts/wait-for-connect-and-controlcenter.sh replicator-us $@
../../scripts/wait-for-connect-and-controlcenter.sh replicator-europe $@

log "Verify we have received the data in all the sales_ topics in EUROPE"
timeout 60 docker container exec broker-europe kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000

log "Verify we have received the data in all the sales_ topics in the US"
timeout 60 docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000
