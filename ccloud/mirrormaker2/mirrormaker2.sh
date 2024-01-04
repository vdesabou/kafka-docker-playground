#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: This example is working starting from CP 5.4 only"
    exit 111
fi

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" "-a -b"



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

log "Start MirrorMaker2 (logs are in mirrormaker.log):"
docker cp ${DIR}/connect-mirror-maker.properties connect:/tmp/connect-mirror-maker.properties
docker exec -i connect /usr/bin/connect-mirror-maker /tmp/connect-mirror-maker.properties > mirrormaker.log 2>&1 &

log "sleeping 30 seconds"
sleep 30

log "Sending messages in A cluster (OnPrem)"
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --broker-list localhost:9092 --topic sales_A

log "Consumer with group my-consumer-group reads 10 messages in A cluster (OnPrem)"
docker exec -i connect bash -c "kafka-console-consumer --bootstrap-server broker1:9092 --whitelist 'sales_A' --from-beginning --max-messages 10 --consumer-property group.id=my-consumer-group"

log "sleeping 70 seconds"
sleep 70

log "Sending messages in A cluster (OnPrem)"
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --broker-list localhost:9092 --topic sales_A

sleep 30

log "Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset (sync.group.offsets.enabled = true)"
playground topic consume --topic sales_A --min-expected-messages 10 --timeout 60