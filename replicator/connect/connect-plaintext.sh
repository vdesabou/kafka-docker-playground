#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Sending sales in Europe cluster"

seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i connect-europe bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-console-producer --broker-list broker-us:9092 --topic sales_US --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"


log "Consolidating all sales in the US"

docker container exec connect-us \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .


log "Consolidating all sales in Europe"

docker container exec connect-europe \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-us-to-europe",
          "src.kafka.bootstrap.servers": "broker-us:9092",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_US"
          }' \
     http://localhost:8083/connectors/replicate-us-to-europe/config | jq .

sleep 120

log "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec -i connect-europe bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist 'sales_.*' --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar;  kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_.*' --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"

