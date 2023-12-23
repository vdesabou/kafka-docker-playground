#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
playground connector create-or-update --connector hdfs-sink << EOF
{
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
}
EOF


log "Sending messages to topic test_hdfs"
playground topic produce -t test_hdfs --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

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
playground connector create-or-update --connector hdfs2-source << EOF
{
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
          "transforms.AddPrefix.replacement" : "copy_of_\$0"
          }
EOF

sleep 10

log "Verifying topic copy_of_test_hdfs"
playground topic consume --topic copy_of_test_hdfs --min-expected-messages 9 --timeout 60
