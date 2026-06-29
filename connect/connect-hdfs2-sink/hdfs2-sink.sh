#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget -q https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
playground container exec --container namenode --command "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
playground connector create-or-update --connector hdfs-sink  << EOF
{
  "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
  "tasks.max":"1",
  "topics":"hdfs-topic",
  "store.url":"hdfs://namenode:8020",
  "flush.size":"3",
  "hadoop.conf.dir":"/etc/hadoop/",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
  "rotate.interval.ms":"120000",
  "logs.dir":"/tmp",
  "hive.integration": "true",
  "hive.metastore.uris": "thrift://hive-metastore:9083",
  "hive.database": "testhive",
  "key.converter":"org.apache.kafka.connect.storage.StringConverter",
  "value.converter":"io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url":"http://schema-registry:8081",
  "schema.compatibility":"BACKWARD"
}
EOF


log "Sending messages to topic hdfs-topic"
playground topic produce -t hdfs-topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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

log "Listing content of /topics/hdfs-topic/partition=0 in HDFS"
playground container exec --container namenode --command "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/hdfs-topic/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
playground container exec --container namenode --command "/opt/hadoop-2.7.4/bin/hadoop fs -copyToLocal /topics/hdfs-topic/partition=0/hdfs-topic+0+0000000000+0000000002.avro /tmp"
docker cp namenode:/tmp/hdfs-topic+0+0000000000+0000000002.avro /tmp/

playground  tools read-avro-file --file /tmp/hdfs-topic+0+0000000000+0000000002.avro

log "Check data with beeline"
playground container exec --container hive-server --command "beeline" > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table hdfs-topic;
select * from hdfs-topic;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
