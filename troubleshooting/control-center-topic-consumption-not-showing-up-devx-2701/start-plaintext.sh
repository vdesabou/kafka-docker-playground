#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/orders-template.avro > ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/shipments-template.avro > ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/shipments.avro

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create topic orders"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "orders",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 500,
                "iterations": "-1",
                "tasks.max": "1",
                "schema.filename" : "/tmp/schemas/orders.avro",
                "schema.keyfield" : "orderid"
            }' \
      http://localhost:8083/connectors/datagen/config | jq .



log "Checking messages from topic orders with MonitoringConsumerInterceptor in background"
docker exec -i connect bash -c 'export CLASSPATH=/usr/share/java/monitoring-interceptors/*; kafka-console-consumer --bootstrap-server broker:9092 --topic orders --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property group.id=myapp --from-beginning > /dev/null 2>&1 &'
