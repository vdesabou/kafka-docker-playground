#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

HIVE_INTEGRATION="true"
if version_gt $CONNECTOR_TAG "1.9.99"
then
  logwarn "HDFS3 Sink Connector versions 2.0.0 and above are compatible only with Hive Metastore versions 4.0.1 and later. Use hdfs3-sink-hive4.sh if you require hive integration"
  logwarn "skipping Hive integration in this example"
  HIVE_INTEGRATION="false"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}

# HDFS3 sink is not compatible with CFK (Confluent for Kubernetes)
# CFK processes the docker-compose override to create Kubernetes Pods,
# but HDFS datanodes fail to register with the namenode in K8s networking model.
# HDFS cluster requires StatefulSets for persistent node identity, not ephemeral Pods.
if [[ "$PLAYGROUND_ENVIRONMENT" == "cfk" ]]
then
  logwarn "⚠️  HDFS3 sink connector is not compatible with CFK (Confluent for Kubernetes)"
  logwarn "   HDFS requires persistent node registration that K8s Pods cannot maintain"
  logwarn "   This example is for Docker Compose environments only"
  exit 111
fi

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
playground container exec --container namenode --command "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector with Hive integration"
playground connector create-or-update --connector hdfs3-sink  << EOF
{
  "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
  "tasks.max":"1",
  "topics":"hdfs-topic",
  "store.url":"hdfs://namenode:9000",
  "flush.size":"3",
  "hadoop.conf.dir":"/etc/hadoop/",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
  "rotate.interval.ms":"120000",
  "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
  "logs.dir":"/tmp",
  "hive.integration": "$HIVE_INTEGRATION",
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
playground container exec --container namenode --command "/opt/hadoop-3.1.3/bin/hdfs dfs -ls /topics/hdfs-topic/partition=0"
    
log "Getting one of the avro files locally and displaying content with avro-tools"
playground container exec --container namenode --command "/opt/hadoop-3.1.3/bin/hadoop fs -copyToLocal /topics/hdfs-topic/partition=0/hdfs-topic+0+0000000000+0000000002.avro /tmp"
playground container cp --source namenode:/tmp/hdfs-topic+0+0000000000+0000000002.avro --destination /tmp/

playground  tools read-avro-file --file /tmp/hdfs-topic+0+0000000000+0000000002.avro


if ! version_gt $CONNECTOR_TAG "1.9.99"
then
  sleep 60
  log "Check data with beeline"
  playground container exec --container hive-server --command "beeline" > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
-- the connector sanitizes the topic name when creating the hive table: hdfs-topic -> hdfs_topic
show create table hdfs_topic;
select * from hdfs_topic;
EOF
  cat /tmp/result.log
  grep "value1" /tmp/result.log
fi