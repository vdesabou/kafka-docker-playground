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

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-perf-issue.yml"

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

log "Create topic products-schema"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "products-schema",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "true",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/products.avro",
                "schema.keyfield" : "productid"
            }' \
      http://localhost:8083/connectors/datagen-products-schema/config | jq

wait_for_datagen_connector_to_inject_data "products-schema" "10"

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating JSON CONVERTER (schemas.enable=false) HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"products",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"20001",
               "hadoop.conf.dir":"/etc/hadoop/",
               "format.class" : "io.confluent.connect.hdfs.json.JsonFormat",
               "storage.class": "io.confluent.connect.hdfs.storage.HdfsStorage",
               "rotate.interval.ms": "100",
               "logs.dir":"/tmp/json",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink-json-converter/config | jq .


SECONDS=0
wait_for_connector_to_finish hdfs-sink-json-converter
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"


log "Creating JSON CONVERTER (schemas.enable=true) HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"products-schema",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"20001",
               "hadoop.conf.dir":"/etc/hadoop/",
               "format.class" : "io.confluent.connect.hdfs.json.JsonFormat",
               "storage.class": "io.confluent.connect.hdfs.storage.HdfsStorage",
               "rotate.interval.ms": "100",
               "logs.dir":"/tmp/json",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "true",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink-json-converter-schema/config | jq .

SECONDS=0
wait_for_connector_to_finish hdfs-sink-json-converter-schema
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"


log "Deleting data in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -rm -r /topics/*"

log "Creating STRING CONVERTER HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"products",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"20001",
               "hadoop.conf.dir":"/etc/hadoop/",
               "format.class" : "io.confluent.connect.hdfs.json.JsonFormat",
               "storage.class": "io.confluent.connect.hdfs.storage.HdfsStorage",
               "rotate.interval.ms": "100",
               "logs.dir":"/tmp/string",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter.schemas.enable": "false",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink-string-converter/config | jq .


SECONDS=0
wait_for_connector_to_finish hdfs-sink-string-converter
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"
