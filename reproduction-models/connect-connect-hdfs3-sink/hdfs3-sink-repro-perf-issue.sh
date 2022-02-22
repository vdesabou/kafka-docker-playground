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
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"

if version_gt $TAG_BASE "5.9.0" || [[ "$TAG" = *ubi8 ]]
then
     log "Creating JSON CONVERTER (schemas.enable=false) HDFS Sink connector without Hive integration (not supported with JDK 11)"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"products",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"20001",
                    "rotate.interval.ms": "100",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "format.class" : "io.confluent.connect.hdfs3.json.JsonFormat",
                    "storage.class": "io.confluent.connect.hdfs3.storage.HdfsStorage",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp/json",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink-json-converter/config | jq .
else
     log "Creating JSON CONVERTER (schemas.enable=false) HDFS Sink connector with Hive integration"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"products",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"20000001",
                    "rotate.interval.ms": "100",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "format.class" : "io.confluent.connect.hdfs3.json.JsonFormat",
                    "storage.class": "io.confluent.connect.hdfs3.storage.HdfsStorage",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp/json",
                    "hive.integration": "true",
                    "hive.metastore.uris": "thrift://hive-metastore:9083",
                    "hive.database": "testhive",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink-json-converter/config | jq .
fi

SECONDS=0
wait_for_connector_to_finish hdfs3-sink-json-converter
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"

if version_gt $TAG_BASE "5.9.0" || [[ "$TAG" = *ubi8 ]]
then
     log "Creating JSON CONVERTER (schemas.enable=true) HDFS Sink connector without Hive integration (not supported with JDK 11)"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"products-schema",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"20001",
                    "rotate.interval.ms": "100",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "format.class" : "io.confluent.connect.hdfs3.json.JsonFormat",
                    "storage.class": "io.confluent.connect.hdfs3.storage.HdfsStorage",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp/json",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "true",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink-json-converter-schema/config | jq .
else
     log "Creating JSON CONVERTER (schemas.enable=true) HDFS Sink connector with Hive integration"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"products-schema",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"20000001",
                    "rotate.interval.ms": "100",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "format.class" : "io.confluent.connect.hdfs3.json.JsonFormat",
                    "storage.class": "io.confluent.connect.hdfs3.storage.HdfsStorage",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp/json",
                    "hive.integration": "true",
                    "hive.metastore.uris": "thrift://hive-metastore:9083",
                    "hive.database": "testhive",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "true",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink-json-converter-schema/config | jq .
fi

SECONDS=0
wait_for_connector_to_finish hdfs3-sink-json-converter-schema
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"


log "Deleting data in HDFS"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -rm -r /topics/*"

if version_gt $TAG_BASE "5.9.0" || [[ "$TAG" = *ubi8 ]]
then
     log "Creating STRING CONVERTER HDFS Sink connector without Hive integration (not supported with JDK 11)"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"products",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"20001",
                    "rotate.interval.ms": "100",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "format.class" : "io.confluent.connect.hdfs3.json.JsonFormat",
                    "storage.class": "io.confluent.connect.hdfs3.storage.HdfsStorage",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp/string",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter.schemas.enable": "false",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink-string-converter/config | jq .
else
     log "Creating STRING CONVERTER HDFS Sink connector with Hive integration"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"products",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"20000001",
                    "rotate.interval.ms": "100",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "format.class" : "io.confluent.connect.hdfs3.json.JsonFormat",
                    "storage.class": "io.confluent.connect.hdfs3.storage.HdfsStorage",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp/string",
                    "hive.integration": "true",
                    "hive.metastore.uris": "thrift://hive-metastore:9083",
                    "hive.database": "testhive",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter.schemas.enable": "false",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink-string-converter/config | jq .
fi

SECONDS=0
wait_for_connector_to_finish hdfs3-sink-string-converter
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "It took $ELAPSED"

