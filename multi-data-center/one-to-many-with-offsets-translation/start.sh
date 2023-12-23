#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Sending 20 records in Metrics cluster"
seq -f "sale_%g ${RANDOM}" 20 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-metrics:9092 --topic sales"

log "Consumer with group my-consumer-group reads 10 messages in Metrics cluster"
# Points of interest:
# ConsumerTimestampsInterceptor: ConsumerInterceptor creating the __consumer_timestamps topic and recording the offset-timestamp pair
# __consumer_timestamps is by default created with RF=3 since we have only one broker, we have to defone timestamps.topic.replication.factor=1
docker container exec -i connect-europe bash -c "kafka-console-consumer \
     --bootstrap-server broker-metrics:9092 \
     --topic sales \
     --from-beginning \
     --max-messages 10 \
     --group my-consumer-group \
     --consumer-property interceptor.classes=io.confluent.connect.replicator.offsets.ConsumerTimestampsInterceptor \
     --consumer-property timestamps.topic.replication.factor=1"

# log "Print content of __consumer_timestamps in Metrics cluster after reading 10 messages"
# #key-> consumerGroup: topic-partition
# #value-> timestamp:delta
# docker container exec -i connect-europe bash -c "kafka-console-consumer \
#      --bootstrap-server broker-metrics:9092 \
#      --topic __consumer_timestamps \
#      --from-beginning --max-messages 1  \
#      --property print.key=true \
#      --property key.deserializer=io.confluent.connect.replicator.offsets.GroupTopicPartitionDeserializer \
#      --property value.deserializer=io.confluent.connect.replicator.offsets.TimestampAndDeltaDeserializer"

# Setting up a replication of the sales topic on Metrics to Europe and US (one-to-many replication) with offset transaltions.
# Points of interest:
# - "offset.timestamps.commit: false" preventing the replicator to commit their timestamps in __consumer_timestamp too.
# If not disabled, the US cluster will produce a message into __consuemer_timestamps and the Europe replicator will try to translate this offsets in the destination cluster
# This feature is meaningful when doing an active-active setup or when you need to failback.
# - "offset.translator.batch.period.ms": 5000 (Defaut 60000ms/1m). For demo purpose, set this value to 5s.
log "Replicate from Metrics to Europe"
docker container exec connect-europe \
playground connector create-or-update --connector replicate-metrics-to-europe --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-metrics-to-us",
          "src.kafka.bootstrap.servers": "broker-metrics:9092",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales",
          "offset.timestamps.commit": false,
          "offset.translator.batch.period.ms": 5000 
          }
EOF

log "Replicate from Metrics to US"
docker container exec connect-us \
playground connector create-or-update --connector replicate-metrics-to-us --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-metrics-to-us",
          "src.kafka.bootstrap.servers": "broker-metrics:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales",
          "offset.timestamps.commit": false,
          "offset.translator.batch.period.ms": 5000
          }
EOF

log "Wait for data to be replicated"
sleep 30

## Checking the offsets on the targets clusters
# log "On Europe cluster, my-consumer-group is at offset=10 on the topic-partition sales-0"
# docker container exec -it connect-europe bash -c 'echo "exclude.internal.topics=false" > /tmp/consumer.config && kafka-console-consumer \
#      --consumer.config /tmp/consumer.config \
#      --bootstrap-server broker-europe:9092 \
#      --topic __consumer_offsets \
#      --from-beginning \
#      --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" \
#      --timeout-ms 30000'

# log "On US cluster, my-consumer-group is at offset=10 on the topic-partition sales-0"
# docker container exec -it connect-europe bash -c 'echo "exclude.internal.topics=false" > /tmp/consumer.config && kafka-console-consumer \
#      --consumer.config /tmp/consumer.config \
#      --bootstrap-server broker-us:9092 \
#      --topic __consumer_offsets \
#      --from-beginning \
#      --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" \
#      --timeout-ms 30000'

# On Both cluster the "my-consumer-group" will starts just where it stopped on the metrics cluster.
log "Consumer with group my-consumer-group reads 10 messages in Europe cluster, starting from offset 10"
docker container exec -i connect-europe bash -c "kafka-console-consumer \
     --bootstrap-server broker-europe:9092 \
     --topic sales \
     --max-messages 10  \
     --group my-consumer-group"

log "Consumer with group my-consumer-group reads 10 messages in US cluster, starting from offset 10"
docker container exec -i connect-us bash -c "kafka-console-consumer \
     --bootstrap-server broker-us:9092 \
     --topic sales \
     --max-messages 10  \
     --group my-consumer-group"


