#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_connector_to_finish () {
     connector_name="$1"

     set +e
     MAX_WAIT=3600
     CUR_WAIT=0
     current_offset="-1"
     log_end_offset=$(docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-${connector_name} --describe | grep "${connector_name}" | awk '{print $5}')
     while [[ ! "${current_offset}" = "${log_end_offset}" ]]
     do
          log "⏳ Connector $connector_name processed messages $current_offset/$log_end_offset"
          current_offset=$(docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-${connector_name} --describe | grep "${connector_name}" | awk '{print $4}')
          log_end_offset=$(docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-${connector_name} --describe | grep "${connector_name}" | awk '{print $5}')

          sleep 2
          CUR_WAIT=$(( CUR_WAIT+2 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               logerror "❗❗❗ ERROR: Please troubleshoot"
               exit 1
          fi
     done
     set -e
}

mkdir -p ${DIR}/data/ouput

# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+rw ${DIR}/data

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-perf.yml"

log "Create topic products"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "products",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/products.avro",
                "schema.keyfield" : "productid"
            }' \
      http://localhost:8083/connectors/datagen-products/config | jq

wait_for_datagen_connector_to_inject_data "products" "10"

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file-json.json"

log "Creating JSONConverter FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "products",
               "file": "'"$OUTPUT_FILE"'",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/filestream-json-sink/config | jq .


SECONDS=0
wait_for_connector_to_finish filestream-json-sink
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file-string.json"

log "Creating StringConverter FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "products",
               "file": "'"$OUTPUT_FILE"'",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/filestream-string-sink/config | jq .


SECONDS=0
wait_for_connector_to_finish filestream-string-sink
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"
