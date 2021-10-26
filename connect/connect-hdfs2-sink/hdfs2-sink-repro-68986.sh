#!/bin/bash
set -e

export TAG=5.4.1
export CONNECTOR_TAG=5.4.1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-v1
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

log "Start with 5.4.1"

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-68986.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"my_topic",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"appVersion",
               "rotate.interval.ms":"120000",
               "logs.dir":"/tmp",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"FULL"
          }' \
     http://localhost:8083/connectors/hdfs-sink-repro/config | jq .


log "Run the Java producer-v1"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Get Schema Registry schema"
curl --request GET \
  --url http://localhost:8081/subjects/my_topic-value/versions/1 | jq .

log "Listing content of /topics/my_topic in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/my_topic"

# - issue is the same without Hive integration
# log "Check data with beeline"
# docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
# !connect jdbc:hive2://hive-server:10000/testhive
# hive
# hive
# show create table my_topic;
# select * from my_topic;
# EOF
# cat /tmp/result.log

log "Update to 5.5.3"

export TAG=5.5.3
export CONNECTOR_TAG=5.5.3

source ${DIR}/../../scripts/utils.sh

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../connect/connect-hdfs2-sink/docker-compose.plaintext.yml -f ../../connect/connect-hdfs2-sink/repro-68986/docker-compose.patch.yml --profile control-center  up -d

../../scripts/wait-for-connect-and-controlcenter.sh

log "Set value.converter.connect.meta.data to false"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"my_topic",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"appVersion",
               "rotate.interval.ms":"120000",
               "logs.dir":"/tmp",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "value.converter.connect.meta.data": "false",
               "schema.compatibility":"FULL"
          }' \
     http://localhost:8083/connectors/hdfs-sink-repro/config | jq .

log "Run the Java producer-v1"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing content of /topics/my_topic in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/my_topic"

# sleep 20

# - issue is the same without Hive integration
# log "Check data with beeline"
# docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
# !connect jdbc:hive2://hive-server:10000/testhive
# hive
# hive
# show create table my_topic;
# select * from my_topic;
# EOF
# cat /tmp/result.log

# Notes:
# - issue is the same without Hive integration
# - https://confluentinc.atlassian.net/browse/DGS-486 ? see related GH issue https://github.com/confluentinc/schema-registry/issues/1042 (CP 5.5.3 contains the fix)

# [2021-07-28 07:42:05,120] ERROR WorkerSinkTask{id=hdfs-sink-repro-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting appOS (org.apache.kafka.connect.runtime.WorkerSinkTask)
# java.lang.RuntimeException: org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting appOS
#         at io.confluent.connect.hdfs.TopicPartitionWriter.write(TopicPartitionWriter.java:406)
#         at io.confluent.connect.hdfs.DataWriter.write(DataWriter.java:386)
#         at io.confluent.connect.hdfs.HdfsSinkTask.put(HdfsSinkTask.java:124)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:546)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:326)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:229)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting appOS
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:113)
#         at org.apache.kafka.connect.data.SchemaProjector.projectRequiredSchema(SchemaProjector.java:93)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:73)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:395)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:383)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.project(StorageSchemaCompatibility.java:355)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.write(TopicPartitionWriter.java:383)
#         ... 13 more
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {avro.java.string=String, io.confluent.connect.avro.field.default=true} and target parameters: {avro.java.string=String}
#         at org.apache.kafka.connect.data.SchemaProjector.checkMaybeCompatible(SchemaProjector.java:133)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:60)
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:110)
#         ... 19 more

# With:

#         {
#             "default": "",
#             "name": "appVersion",
#             "type": {
#                 "connect.default": "",
#                 "type": "string"
#             }
#         },

# Error projecting appOS
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {avro.java.string=String, io.confluent.connect.avro.field.default=true} and target parameters: {avro.java.string=String}

# With:

#         {
#             "default": "",
#             "name": "appVersion",
#             "type": {
#                 "type": "string"
#             }
#         },

# Error projecting appVersion
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {avro.java.string=String, io.confluent.connect.avro.field.default=true} and target parameters: {avro.java.string=String}

# With:

     #    {
     #        "default": "",
     #        "name": "appVersion",
     #        "type": "string"
     #    },

# Error projecting appVersion
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {avro.java.string=String, io.confluent.connect.avro.field.default=true} and target parameters: {avro.java.string=String}

# With:

     #    {
     #        "name": "appVersion",
     #        "type": "string"
     #    },

# Error projecting appOS
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {avro.java.string=String, io.confluent.connect.avro.field.default=true} and target parameters: {avro.java.string=String}


# with

# {
#     "fields": [
#         {
#             "name": "appVersion",
#             "type": "string"
#         },
#         {
#             "default": "",
#             "name": "appOS",
#             "type": "string"
#         }
#     ],
#     "name": "Customer",
#     "namespace": "com.github.vdesabou",
#     "type": "record"
# }

# Error projecting appOS
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {avro.java.string=String, io.confluent.connect.avro.field.default=true} and target parameters: {avro.java.string=String}

# if I set "schema.compatibility":"NONE", it works fine


# with customer schema:

# [2021-07-28 09:50:29,573] ERROR WorkerSinkTask{id=hdfs-sink-repro-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:568)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:326)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:229)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.lang.RuntimeException: org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting createdDate
#         at io.confluent.connect.hdfs.TopicPartitionWriter.write(TopicPartitionWriter.java:406)
#         at io.confluent.connect.hdfs.DataWriter.write(DataWriter.java:386)
#         at io.confluent.connect.hdfs.HdfsSinkTask.put(HdfsSinkTask.java:124)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:546)
#         ... 10 more
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting createdDate
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:113)
#         at org.apache.kafka.connect.data.SchemaProjector.projectRequiredSchema(SchemaProjector.java:93)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:73)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:395)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:383)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.project(StorageSchemaCompatibility.java:355)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.write(TopicPartitionWriter.java:383)
#         ... 13 more
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {io.confluent.connect.avro.field.default=true} and target parameters: null
#         at org.apache.kafka.connect.data.SchemaProjector.checkMaybeCompatible(SchemaProjector.java:133)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:60)
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:110)
#         ... 19 more