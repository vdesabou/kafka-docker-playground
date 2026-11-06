#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.3.99"; then
    logwarn "The source (OnPrem) cluster of this example runs in KRaft mode: CP 7.4 or later is required"
    exit 111
fi

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# BOOTSTRAP_SERVERS, CLOUD_KEY and CLOUD_SECRET of the Confluent Cloud cluster: written by start-environment (a subprocess)
source "${DIR}/../../.ccloud/env.delta"



# generate connect-mirror-maker.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ../../ccloud/mirrormaker2/connect-mirror-maker-template.properties > ../../ccloud/mirrormaker2/connect-mirror-maker.properties

log "Creating topic sales_A in Confluent Cloud"
set +e
playground topic delete --topic sales_A
playground topic delete --topic mm2-configs.A.internal
playground topic delete --topic mm2-offsets.A.internal
playground topic delete --topic mm2-status.A.internal
playground topic delete --topic .checkpoints.internal
sleep 3
playground topic create --topic sales_A
set -e

log "Start MirrorMaker2 in broker1 (dedicated mode, logs are in mirrormaker.log):"
playground container cp --source ${DIR}/connect-mirror-maker.properties --destination broker1:/tmp/connect-mirror-maker.properties
docker exec -i broker1 /usr/bin/connect-mirror-maker /tmp/connect-mirror-maker.properties > mirrormaker.log 2>&1 &

log "sleeping 30 seconds"
sleep 30

log "Sending messages in A cluster (OnPrem)"
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --bootstrap-server broker1:9092 --topic sales_A

log "Consumer with group my-consumer-group reads 10 messages in A cluster (OnPrem)"
docker exec -i broker1 kafka-console-consumer --bootstrap-server broker1:9092 --include 'sales_A' --from-beginning --max-messages 10 --timeout-ms 60000 --consumer-property group.id=my-consumer-group

log "sleeping 70 seconds"
sleep 70

log "Sending messages in A cluster (OnPrem)"
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --bootstrap-server broker1:9092 --topic sales_A

sleep 30

log "Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset (sync.group.offsets.enabled = true)"
playground topic consume --topic sales_A --min-expected-messages 10 --timeout 60