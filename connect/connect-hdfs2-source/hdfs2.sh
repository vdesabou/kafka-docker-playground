#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "hdfs.url":"hdfs://hadoop:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/usr/local/hadoop-2.7.1/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "hadoop.home":"/usr/local/hadoop-2.7.1/share/hadoop/common/",
               "logs.dir":"/tmp",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs2-sink/config | jq_docker_cli .


log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /topics/test_hdfs in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /topics/test_hdfs"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
docker cp hadoop:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

log "Creating HDFS Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class":"io.confluent.connect.hdfs2.Hdfs2SourceConnector",
               "tasks.max":"1",
               "store.url":"hdfs://hadoop:9000",
               "hadoop.conf.dir":"/usr/local/hadoop-2.7.1/etc/hadoop/",
               "format.class" : "io.confluent.connect.hdfs2.format.avro.AvroFormat",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms" : "AddPrefix",
               "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex" : ".*",
               "transforms.AddPrefix.replacement" : "copy_of_$0"
          }' \
     http://localhost:8083/connectors/hdfs2-source/config | jq_docker_cli .

sleep 10

log "Verifying topic copy_of_test_hdfs"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic copy_of_test_hdfs --from-beginning --max-messages 9
