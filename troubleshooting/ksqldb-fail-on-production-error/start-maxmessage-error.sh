#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.maxmessage-error.yml"

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

log "Produce a big message to the input topic SENSORS_RAW"
bigmessage=$(cat bigmessage.txt)
echo "{\"id\": \"$bigmessage\", \"timestamp\": \"2020-01-15 02:20:30\", \"enabled\": true}" | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW --compression-codec=snappy --producer-property max.request.size=2097172

sleep 60

log "Checking topic ksql_processing_log"
playground topic consume --topic ksql_processing_log --expected-messages 1

# {"level":"ERROR","logger":"processing.CSAS_SENSORS_3","time":1637601815511,"message":{"type":2,"deserializationError":null,"recordProcessingError":null,"productionError":{"errorMessage":"The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration."},"serializationError":null,"kafkaStreamsThreadError":null}}