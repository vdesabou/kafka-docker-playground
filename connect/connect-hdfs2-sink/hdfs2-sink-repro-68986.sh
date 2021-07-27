#!/bin/bash
set -e

export TAG=5.4.1
export CONNECTOR_TAG=5.4.1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "Start with 5.4.1"

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
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
               "schema.compatibility":"FULL"
          }' \
     http://localhost:8083/connectors/hdfs-sink-repro/config | jq .


log "Sending messages to topic my_topic"
seq -f "{\"f1\": \"value%g\", \"f2\": 0}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"type":"string","name":"f1"},{"default":0,"type":"double","name":"f2"}],"type":"record","name":"myrecord"}'

sleep 10

log "Listing content of /topics/my_topic in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/my_topic"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hadoop fs -copyToLocal /topics/my_topic/f1=value1/my_topic+0+0000000000+0000000000.avro /tmp"
docker cp namenode:/tmp/my_topic+0+0000000000+0000000000.avro /tmp/

docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/my_topic+0+0000000000+0000000000.avro

log "Check data with beeline"
docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table my_topic;
select * from my_topic;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Update to 5.5.3"

export TAG=5.5.3
export CONNECTOR_TAG=5.5.3

source ${DIR}/../../scripts/utils.sh

docker-compose -f ../../environment/plaintext/docker-compose.yml -f /Users/vsaboulin/Documents/github/kafka-docker-playground/connect/connect-hdfs2-sink/docker-compose.plaintext.yml --profile control-center  up -d

../../scripts/wait-for-connect-and-controlcenter.sh

log "Send some messages"
seq -f "{\"f1\": \"value%g\", \"f2\": 0}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"type":"string","name":"f1"},{"default":0,"type":"double","name":"f2"}],"type":"record","name":"myrecord"}'

sleep 10

log "Listing content of /topics/my_topic in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/my_topic"


log "Check data with beeline"
docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table my_topic;
select * from my_topic;
EOF
cat /tmp/result.log
