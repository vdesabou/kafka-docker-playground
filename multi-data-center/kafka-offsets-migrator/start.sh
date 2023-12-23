#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f offset_translator.py ]
then
     log "Downloading offset_translator.py"
     wget https://raw.githubusercontent.com/bb01100100/kafka-offsets-migrator/master/offset_translator.py
fi

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Sending 20 records in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 20 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"

log "Consumer with group my-consumer-group reads 10 messages in Europe cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist 'sales_EUROPE' --from-beginning --max-messages 10 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092 --consumer-property group.id=my-consumer-group"

log "Replicate from Europe to US"
docker container exec connect-us \
playground connector create-or-update --connector replicate-europe-to-us --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
          "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }
EOF

log "Wait for data to be replicated"
sleep 30

log "Calling kafka-offsets-migrator"
docker container exec -i connect-us bash -c "pip3 install -U -r /tmp/requirements.txt && python /tmp/offset_translator.py --source-broker broker-europe:9092 --dest-broker broker-us:9092 --group my-consumer-group --topic sales_EUROPE"

log "Consumer with group my-consumer-group reads 10 messages in US cluster, it should start from previous offset"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_EUROPE' --max-messages 10 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092 --consumer-property group.id=my-consumer-group"
