#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.plaintext.yml" -a -b

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

# generate connect-mirror-maker.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/connect-mirror-maker-template-repro-77222.properties > ${DIR}/connect-mirror-maker.properties

log "Creating topic sales_A in Confluent Cloud"
set +e
delete_topic sales_A
delete_topic mm2-configs.A.internal
delete_topic mm2-offsets.A.internal
delete_topic mm2-status.A.internal
delete_topic .checkpoints.internal
sleep 3
create_topic sales_A
set -e

log "Start MirrorMaker2 (logs are in mirrormaker.log):"
docker cp ${DIR}/connect-mirror-maker.properties connect:/tmp/connect-mirror-maker.properties
docker exec -i connect /usr/bin/connect-mirror-maker /tmp/connect-mirror-maker.properties > mirrormaker.log 2>&1 &

log "sleeping 30 seconds"
sleep 30

log "Sending messages in A cluster (OnPrem)"
docker exec broker1 kafka-producer-perf-test --topic sales_A --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker1:9092

log "Consumer with group my-consumer-group reads 10 messages in A cluster (OnPrem)"
docker exec -i broker1 bash -c "kafka-console-consumer --bootstrap-server broker1:9092 --whitelist 'sales_A' --from-beginning --max-messages 10 --consumer-property group.id=my-consumer-group"

log "sleeping 70 seconds"
sleep 70

log "Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset (sync.group.offsets.enabled = true)"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" broker1 bash -c 'kafka-console-consumer --topic sales_A --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --max-messages 10 --consumer-property group.id=my-consumer-group'

tail -f mirrormaker.log | grep "ERROR"

# Repro:
# [2021-10-12 11:00:54,454] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30625 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 11:00:54,457] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 11:01:59,391] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30641 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 11:01:59,392] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 11:03:04,326] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30769 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 11:03:04,327] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)