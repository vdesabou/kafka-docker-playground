#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# https://issues.apache.org/jira/browse/AVRO-2817

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90283-schemabuilderexception-invalid-default-value.yml"


log "Register schema for customer_avro, which is wrong but was possible to register with CP 5.3.3 (avro 1.8.1)"
curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"type\":\"record\",\"namespace\":\"com.github.vdesabou\",\"name\":\"Customer\",\"fields\":[{\"type\":\"string\",\"name\":\"f1\"},{\"default\":null,\"type\":\"string\",\"name\":\"partition_date\"}]}"
}'

# {
#     "name": "Customer",
#     "namespace": "com.github.vdesabou",
#     "type": "record",
#     "fields": [
#         {
#             "name": "f1",
#             "type": "string"
#         },
#         {
#             "name": "partition_date",
#             "type": "string",
#             "default": null
#         }
#     ]
# }

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"

if version_gt $TAG_BASE "5.9.0" || [[ "$TAG" = *ubi8 ]]
then
     log "Creating HDFS Sink connector without Hive integration (not supported with JDK 11)"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"customer_avro",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"3",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "partitioner.class":"io.confluent.connect.storage.partitioner.FieldPartitioner",
                    "partition.field.name":"f1",
                    "rotate.interval.ms":"120000",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "schema.compatibility":"BACKWARD",
                    "format.class": "io.confluent.connect.hdfs3.parquet.ParquetFormat"
               }' \
          http://localhost:8083/connectors/hdfs3-sink/config | jq .
else
     log "Creating HDFS Sink connector with Hive integration"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"1",
                    "topics":"customer_avro",
                    "store.url":"hdfs://namenode:9000",
                    "flush.size":"3",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "partitioner.class":"io.confluent.connect.storage.partitioner.FieldPartitioner",
                    "partition.field.name":"f1",
                    "rotate.interval.ms":"120000",
                    "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
                    "logs.dir":"/tmp",
                    "hive.integration": "true",
                    "hive.metastore.uris": "thrift://hive-metastore:9083",
                    "hive.database": "testhive",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs3-sink/config | jq .
fi

seq -f "{\"f1\": \"value%g\",\"partition_date\": \"test\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customer_avro --property value.schema='{"type":"record","namespace":"com.github.vdesabou","name":"Customer","fields":[{"type":"string","name":"f1"},{"default":null,"type":"string","name":"partition_date"}]}'

sleep 10


# [2022-02-03 15:05:22,626] ERROR [hdfs3-sink|task-0] WorkerSinkTask{id=hdfs3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:190)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:206)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:132)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:497)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:474)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:188)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:237)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.SchemaBuilderException: Invalid default value
#         at org.apache.kafka.connect.data.SchemaBuilder.defaultValue(SchemaBuilder.java:131)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1890)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1629)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1760)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1605)
#         at io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1286)
#         at io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:114)
#         at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:541)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$2(WorkerSinkTask.java:497)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:156)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:190)
#         ... 13 more
# Caused by: org.apache.kafka.connect.errors.DataException: Invalid value: null used for required field: "null", schema type: STRING
#         at org.apache.kafka.connect.data.ConnectSchema.validateValue(ConnectSchema.java:220)
#         at org.apache.kafka.connect.data.ConnectSchema.validateValue(ConnectSchema.java:213)
#         at org.apache.kafka.connect.data.SchemaBuilder.defaultValue(SchemaBuilder.java:129)
#         ... 24 more

log "Listing content of /topics/customer_avro in HDFS"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -ls /topics/customer_avro"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hadoop fs -copyToLocal /topics/customer_avro/f1=value1/customer_avro+0+0000000000+0000000000.avro /tmp"
docker cp namenode:/tmp/customer_avro+0+0000000000+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/customer_avro+0+0000000000+0000000000.avro

if version_gt $TAG_BASE "5.9.0" || [[ "$TAG" = *ubi8 ]]
then
     :
else
     sleep 60
     log "Check data with beeline"
docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table customer_avro;
select * from customer_avro;
EOF
     cat /tmp/result.log
     grep "value1" /tmp/result.log
fi