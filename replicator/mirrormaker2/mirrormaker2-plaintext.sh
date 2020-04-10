#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "TOREMOVE: showing docker versions"
docker -v
docker-compose -v

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --broker-list localhost:9092 --topic sales_US

log "Consolidating all sales (logs are in /tmp/mirrormaker.log):"

# run in detach mode -d
docker exec -d connect-us bash -c '/usr/bin/connect-mirror-maker /etc/kafka/connect-mirror-maker.properties > /tmp/mirrormaker.log 2>&1'

# docker exec connect-us bash -c '/usr/bin/connect-mirror-maker /etc/kafka/connect-mirror-maker.properties'

log "sleeping 120 seconds"
sleep 120

# Topic Renaming

# By default MM2 renames source topics to be prefixed with the source cluster name. e.g. if topic foo came from cluster A then it would be named A.foo on the destination. In the current release (5.4) MM2 does not support any different topic naming strategies out of the box.

log "Verify we have received the data in topic US.sales_US in EUROPE"
timeout 60 docker container exec broker-europe kafka-console-consumer --bootstrap-server localhost:9092 --topic "US.sales_US" --from-beginning --max-messages 10

log "Verify we have received the data in topic EUROPE.sales_EUROPE topics in the US"
timeout 60 docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --topic "EUROPE.sales_EUROPE" --from-beginning --max-messages 10

log "Copying mirrormaker logs to /tmp/mirrormaker.log"
docker cp connect-us:/tmp/mirrormaker.log /tmp/mirrormaker.log