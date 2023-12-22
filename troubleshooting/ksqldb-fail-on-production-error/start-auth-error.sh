#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

#playground start-environment --environment sasl-plain --docker-compose-override-file "${PWD}/docker-compose.plaintext.autherror.yml"

docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ${DIR}/docker-compose.plaintext.autherror.yml --profile control-center --profile ksqldb up -d zookeeper broker schema-registry connect

../../scripts/wait-for-connect-and-controlcenter.sh

# Allow ksqlDB to discover the cluster:
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation DescribeConfigs --cluster --command-config /tmp/client.properties
# Allow ksqlDB to read the input topics:
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation Read --resource-pattern-type prefixed --topic SENSORS_RAW --command-config /tmp/client.properties
# Allow ksqlDB to manage output topics:
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation All --resource-pattern-type prefixed --topic ksql-fraud- --command-config /tmp/client.properties
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation All --resource-pattern-type prefixed --topic SENSORS --command-config /tmp/client.properties
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation All --resource-pattern-type prefixed --topic _confluent-monitoring --command-config /tmp/client.properties
# Allow ksqlDB to manage its own internal topics and consumer groups:
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation All --resource-pattern-type prefixed --topic _confluent-ksql-playground_ --group _confluent-ksql-playground_ --command-config /tmp/client.properties
# Allow ksqlDB to manage its record processing log topic, if configured:
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --operation All --topic playground_ksql_processing_log --command-config /tmp/client.properties
# Allow ksqlDB to produce to the command topic:
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:ksqldb --producer --transactional-id '*' --topic _confluent-ksql-playground__command_topic --command-config /tmp/client.properties

docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ${DIR}/docker-compose.plaintext.autherror.yml --profile control-center --profile ksqldb up -d

log "Sleep 60 seconds to let ksql to start"
sleep 60

log "Create the input topic with a stream"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF
CREATE STREAM SENSORS_RAW (id VARCHAR, timestamp VARCHAR, enabled BOOLEAN)
    WITH (KAFKA_TOPIC = 'SENSORS_RAW',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

CREATE STREAM SENSORS AS
    SELECT
        ID, TIMESTAMP, ENABLED
    FROM SENSORS_RAW
    PARTITION BY ID;
EOF

log "Denying principal to use output topic SENSORS"
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --deny-principal User:ksqldb --operation All --topic SENSORS --command-config /tmp/client.properties

log "Produce events to the input topic SENSORS_RAW"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW --producer.config /tmp/client.properties << EOF
{"id": "e7f45046-ad13-404c-995e-1eca16742801", "timestamp": "2020-01-15 02:20:30", "enabled": true}
{"id": "835226cf-caf6-4c91-a046-359f1d3a6e2e", "timestamp": "2020-01-15 02:25:30", "enabled": true}
{"id": "835226cf-caf6-4c91-a046-359f1d3a6e2e", "timestamp": "2020-01-15 02:25:30", "enabled": true}
EOF

sleep 30

log "Checking topic playground_ksql_processing_log"
playground topic consume --topic playground_ksql_processing_log --min-expected-messages 1 --timeout 60

# {"level":"ERROR","logger":"processing.CSAS_SENSORS_3.ksql.logger.thread.exception.uncaught","time":1637600229215,"message":{"type":4,"deserializationError":null,"recordProcessingError":null,"productionError":null,"serializationError":null,"kafkaStreamsThreadError":{"errorMessage":"Unhandled exception caught in streams thread","threadName":"_confluent-ksql-playground_query_CSAS_SENSORS_3-cc09a551-5ef3-4a39-9673-38a35e3ede58-StreamThread-1","cause":["Error encountered sending record to topic SENSORS for task 0_0 due to:\norg.apache.kafka.common.errors.TopicAuthorizationException: Not authorized to access topics: [SENSORS]\nWritten offsets would not be recorded and no more records would be sent since this is a fatal error.","Not authorized to access topics: [SENSORS]"]}}}
