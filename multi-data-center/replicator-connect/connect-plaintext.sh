#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "$PWD/docker-compose.mdc-plaintext.yml"

log "Sending sales in Europe cluster"

seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i connect-europe bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-console-producer --broker-list broker-us:9092 --topic sales_US --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"


log "Consolidating all sales in the US"

docker container exec connect-us \
playground connector create-or-update --connector replicate-europe-to-us << EOF
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


log "Consolidating all sales in Europe"

docker container exec connect-europe \
playground connector create-or-update --connector replicate-us-to-europe << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-us-to-europe",
          "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
          "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
          "src.kafka.bootstrap.servers": "broker-us:9092",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_US"
          }
EOF

sleep 120

log "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec -i connect-europe bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist 'sales_.*' --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar;  kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_.*' --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"



# docker container exec -i control-center bash -c "control-center-console-consumer /etc/confluent-control-center/control-center.properties --topic --from-beginning _confluent-monitoring"

