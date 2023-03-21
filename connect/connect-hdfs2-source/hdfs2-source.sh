#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
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
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink/config | jq .


log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /topics/test_hdfs in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/test_hdfs"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
docker cp namenode:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

log "Check data with beeline"
docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table test_hdfs;
select * from test_hdfs;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Creating HDFS Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.hdfs2.Hdfs2SourceConnector",
          "tasks.max":"1",
          "store.url":"hdfs://namenode:8020",
          "hadoop.conf.dir":"/etc/hadoop/",
          "format.class" : "io.confluent.connect.hdfs2.format.avro.AvroFormat",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "transforms" : "AddPrefix",
          "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
          "transforms.AddPrefix.regex" : ".*",
          "transforms.AddPrefix.replacement" : "copy_of_$0"
          }' \
     http://localhost:8083/connectors/hdfs2-source/config | jq .

sleep 10

log "Verifying topic copy_of_test_hdfs"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic copy_of_test_hdfs --from-beginning --max-messages 9
