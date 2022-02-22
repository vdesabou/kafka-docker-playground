#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure control-center is not disabled
unset DISABLE_CONTROL_CENTER

${DIR}/../../reproduction-models/ccloud-environment/start.sh "${PWD}/docker-compose.plaintext.repro-77222.yml" -a -b

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

log "Creating topic my-topic in Confluent Cloud"
set +e
delete_topic my-topic
delete_topic mm2-configs.A.internal
delete_topic mm2-offsets.A.internal
delete_topic mm2-status.A.internal
delete_topic .checkpoints.internal
sleep 3
create_topic my-topic
set -e

# log "Create topic my-topic with partition 6"
# docker exec connect bash -c "export KAFKA_LOG4J_OPTS='';kafka-topics --create --topic my-topic --bootstrap-server broker1:9092 --replication-factor 3 --partitions 6"

log "Start MirrorMaker2 (logs are in mirrormaker.log):"
docker cp ${DIR}/connect-mirror-maker.properties connect:/tmp/connect-mirror-maker.properties
docker exec -i connect /usr/bin/connect-mirror-maker /tmp/connect-mirror-maker.properties > mirrormaker.log 2>&1 &

log "sleeping 30 seconds"
sleep 30

log "Sending messages in A cluster (OnPrem)"
docker exec connect bash -c "export KAFKA_LOG4J_OPTS='';kafka-producer-perf-test --topic my-topic --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker1:9092"

log "Consumer with group my-consumer-group reads 10 messages in A cluster (OnPrem)"
docker exec -i connect bash -c "export KAFKA_LOG4J_OPTS='';kafka-console-consumer --bootstrap-server broker1:9092 --whitelist 'my-topic' --from-beginning --max-messages 10 --consumer-property group.id=my-consumer-group"

log "sleeping 70 seconds"
sleep 70

log "Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset (sync.group.offsets.enabled = true)"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" connect bash -c 'kafka-console-consumer --topic my-topic --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --max-messages 10 --property print.offset=true --consumer-property group.id=my-consumer-group'

tail -f mirrormaker.log | grep "ERROR"

# https://confluentinc.atlassian.net/browse/CCDB-3071
# https://issues.apache.org/jira/browse/KAFKA-12226


# Repro:
# [2021-10-12 11:00:54,454] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30625 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 11:00:54,457] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 11:01:59,391] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30641 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 11:01:59,392] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 11:03:04,326] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30769 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 11:03:04,327] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)

# with
# A.offset.flush.timeout.ms=45000
# B.offset.flush.timeout.ms=45000
# [2021-10-12 16:30:45,302] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 14225 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:30:45,312] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:32:30,244] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 13393 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:32:30,251] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:34:15,190] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 12689 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:34:15,197] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:36:00,130] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 14161 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:36:00,133] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)

# With:

# A.offset.flush.interval.ms=30000
# B.offset.flush.interval.ms=30000
# A.offset.flush.timeout.ms=45000
# B.offset.flush.timeout.ms=45000

# Processed a total of 10 messages
# [2021-10-12 16:50:58,645] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 14545 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:50:58,652] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:52:13,620] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 13905 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:52:13,628] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:53:28,594] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 13713 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:53:28,602] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:54:43,569] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 14097 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:54:43,573] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 16:55:58,541] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 15185 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 16:55:58,542] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)


# A.offset.flush.interval.ms=30000
# B.offset.flush.interval.ms=30000
# A.offset.flush.timeout.ms=60000
# B.offset.flush.timeout.ms=60000

# Processed a total of 10 messages
# [2021-10-12 17:15:56,548] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 8545 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 17:15:56,561] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 17:17:26,529] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 6785 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 17:17:26,539] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 17:18:56,507] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 13953 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 17:18:56,516] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-12 17:20:26,482] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 7297 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 17:20:26,488] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)

# A.offset.flush.interval.ms=30000
# B.offset.flush.interval.ms=30000
# A.offset.flush.timeout.ms=90000
# B.offset.flush.timeout.ms=90000

# 2021-10-12 19:17:21,083] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 8913 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-12 19:17:21,140] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)


# getting same issue with replicator:

# [2021-10-13 10:31:40,576] INFO WorkerSourceTask{id=replicator-0} flushing 30721 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 10:31:45,576] ERROR WorkerSourceTask{id=replicator-0} Failed to flush, timed out while waiting for producer to flush outstanding 28666 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 10:31:45,578] ERROR WorkerSourceTask{id=replicator-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 10:32:43,265] INFO Found matching topics: [executable-products, __consumer_timestamps] (io.confluent.connect.replicator.NewTopicMonitorThread)
# [2021-10-13 10:32:45,511] INFO WorkerSourceTask{id=replicator-0} flushing 30721 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 10:32:50,511] ERROR WorkerSourceTask{id=replicator-0} Failed to flush, timed out while waiting for producer to flush outstanding 28711 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 10:32:50,512] ERROR WorkerSourceTask{id=replicator-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)

# with original settings + 32 partitions + 100 tasks:

# [2021-10-13 13:00:35,187] ERROR WorkerSourceTask{id=MirrorSourceConnector-9} Failed to flush, timed out while waiting for producer to flush outstanding 1 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:00:35,188] ERROR WorkerSourceTask{id=MirrorSourceConnector-9} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)

# with original settings + 1 partition (default) + 100 tasks:

# [2021-10-13 13:06:13,386] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30737 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:06:13,387] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 13:07:18,320] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 30577 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:07:18,322] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)


# with original settings + 6 partitions (same as ccloud) + 100 tasks:

# [2021-10-13 13:12:30,254] ERROR WorkerSourceTask{id=MirrorSourceConnector-3} Failed to flush, timed out while waiting for producer to flush outstanding 15296 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:12:30,254] ERROR WorkerSourceTask{id=MirrorSourceConnector-3} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 13:12:35,254] ERROR WorkerSourceTask{id=MirrorSourceConnector-2} Failed to flush, timed out while waiting for producer to flush outstanding 13376 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:12:35,255] ERROR WorkerSourceTask{id=MirrorSourceConnector-2} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 13:12:40,256] ERROR WorkerSourceTask{id=MirrorSourceConnector-1} Failed to flush, timed out while waiting for producer to flush outstanding 9776 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:12:40,256] ERROR WorkerSourceTask{id=MirrorSourceConnector-1} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 13:12:45,257] ERROR WorkerSourceTask{id=MirrorSourceConnector-5} Failed to flush, timed out while waiting for producer to flush outstanding 13200 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:12:45,258] ERROR WorkerSourceTask{id=MirrorSourceConnector-5} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 13:12:50,258] ERROR WorkerSourceTask{id=MirrorSourceConnector-4} Failed to flush, timed out while waiting for producer to flush outstanding 10256 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:12:50,258] ERROR WorkerSourceTask{id=MirrorSourceConnector-4} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)
# [2021-10-13 13:12:55,259] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to flush, timed out while waiting for producer to flush outstanding 1840 messages (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-10-13 13:12:55,259] ERROR WorkerSourceTask{id=MirrorSourceConnector-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter)