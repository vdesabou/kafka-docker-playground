#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "Building Hadoop Docker image (replacing if exists)"
cd ../../connect/connect-hdfs3-sink
docker build -t kdp/hadoop:3.3.6 .
rm -f hadoop-config/hiveserver2.pid
cd -



PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.hive4.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
playground container exec --container namenode --command "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector with Hive integration"
playground connector create-or-update --connector hdfs3-sink  << EOF
{
    "connector.class": "io.confluent.connect.hdfs3.Hdfs3SinkConnector",
    "tasks.max": "1",
    "topics": "hdfs-topic",
    "store.url": "hdfs://namenode:9000",
    "flush.size": "3",
    "hadoop.conf.dir": "/etc/hadoop/",
    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
    "rotate.interval.ms": "120000",
    "hadoop.home": "/opt/hadoop",
    "logs.dir": "/tmp",
    "hive.integration": "true",
    "hive.metastore.uris": "thrift://hive-metastore:9083",
    "hive.database": "testhive",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "schema.compatibility": "BACKWARD"
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
playground container exec --container namenode --command "/opt/hadoop/bin/hdfs dfs -ls /topics/hdfs-topic/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
playground container exec --container namenode --command "/opt/hadoop/bin/hadoop fs -copyToLocal /topics/hdfs-topic/partition=0/hdfs-topic+0+0000000000+0000000002.avro /tmp"
playground container cp --source namenode:/tmp/hdfs-topic+0+0000000000+0000000002.avro --destination /tmp/

playground  tools read-avro-file --file /tmp/hdfs-topic+0+0000000000+0000000002.avro


sleep 60
log "Check data with beeline - comprehensive verification"
playground container exec --container hive-server --command "beeline" > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000
hive
hive

-- Check if testhive database exists
SHOW DATABASES;

-- Switch to testhive database
USE testhive;

-- Check if hdfs-topic table exists
SHOW TABLES;

-- Show the table structure
SHOW CREATE TABLE hdfs-topic;

-- Describe the table schema
DESCRIBE hdfs-topic;

-- Count total records
SELECT COUNT(*) as total_records FROM hdfs-topic;

-- Show sample data
SELECT * FROM hdfs-topic LIMIT 10;

-- Show data grouped by partition
SELECT partition, COUNT(*) as record_count FROM hdfs-topic GROUP BY partition;

-- Show the location of the table
SHOW TBLPROPERTIES hdfs-topic;

!quit
EOF

log "Displaying beeline results"
cat /tmp/result.log

log "Verifying data was written correctly"
if grep -q "value1" /tmp/result.log; then
    log "✅ SUCCESS: Data found in Hive table"
else
    log "❌ ERROR: Data not found in Hive table"
fi

if grep -q "hdfs-topic" /tmp/result.log; then
    log "✅ SUCCESS: Hive table created successfully"
else
    log "❌ ERROR: Hive table not found"
fi

if grep -q "testhive" /tmp/result.log; then
    log "✅ SUCCESS: Hive database created successfully"
else
    log "❌ ERROR: Hive database not found"
fi

