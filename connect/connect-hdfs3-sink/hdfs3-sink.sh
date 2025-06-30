#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector with Hive integration"
playground connector create-or-update --connector hdfs3-sink  << EOF
{
  "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
  "tasks.max":"1",
  "topics":"test_hdfs",
  "store.url":"hdfs://namenode:9000",
  "flush.size":"3",
  "hadoop.conf.dir":"/etc/hadoop/",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
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

log "Listing content of /topics/test_hdfs/partition=0 in HDFS"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -ls /topics/test_hdfs/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hadoop fs -copyToLocal /topics/test_hdfs/partition=0/test_hdfs+0+0000000000+0000000002.avro /tmp"
docker cp namenode:/tmp/test_hdfs+0+0000000000+0000000002.avro /tmp/

playground  tools read-avro-file --file /tmp/test_hdfs+0+0000000000+0000000002.avro


sleep 60
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
