#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/orders-template.avro > ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/shipments-template.avro > ${DIR}/../../ksqldb/benchmarking-scenarios/schemas/shipments.avro

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Create topic rbac_orders"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      -u connectorSubmitter:connectorSubmitter \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "rbac_orders",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 500,
                "iterations": "-1",
                "tasks.max": "1",
                "schema.filename" : "/tmp/schemas/orders.avro",
                "schema.keyfield" : "orderid",
                "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorSA\" password=\"connectorSA\" metadataServerUrls=\"http://broker:8091\";"
            }' \
      http://localhost:8083/connectors/my-rbac-connector/config | jq .



log "Checking messages from topic rbac_orders with MonitoringConsumerInterceptor in background"
docker exec -i connect bash -c 'export CLASSPATH=/usr/share/java/monitoring-interceptors/*; kafka-console-consumer --bootstrap-server broker:9092 --topic rbac_orders --consumer.config /etc/kafka/secrets/client_without_interceptors.config --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.security.protocol=SASL_PLAINTEXT --consumer-property confluent.monitoring.interceptor.sasl.mechanism=PLAIN --consumer-property confluent.monitoring.interceptor.sasl.jaas.config="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"admin\" password=\"admin-secret\";" --consumer-property group.id=myapp --from-beginning > /dev/null 2>&1 &'
