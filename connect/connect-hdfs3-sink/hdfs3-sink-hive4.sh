#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "Building Hadoop Docker image (replacing if exists)"
docker build -t kdp/hadoop:3.3.6 ${DIR}

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.official-docker.yml"
sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector with Hive integration"
playground connector create-or-update --connector hdfs3-sink  << EOF
{
    "connector.class": "io.confluent.connect.hdfs3.Hdfs3SinkConnector",
    "tasks.max": "1",
    "topics": "test_hdfs",
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
docker exec namenode bash -c "/opt/hadoop/bin/hdfs dfs -ls /topics/test_hdfs/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode bash -c "/opt/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/partition=0/test_hdfs+0+0000000000+0000000002.avro /tmp"
docker cp namenode:/tmp/test_hdfs+0+0000000000+0000000002.avro /tmp/

playground  tools read-avro-file --file /tmp/test_hdfs+0+0000000000+0000000002.avro


sleep 60
log "Check data with beeline - comprehensive verification"
docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000
hive
hive

-- Check if testhive database exists
SHOW DATABASES;

-- Switch to testhive database
USE testhive;

-- Check if test_hdfs table exists
SHOW TABLES;

-- Show the table structure
SHOW CREATE TABLE test_hdfs;

-- Describe the table schema
DESCRIBE test_hdfs;

-- Count total records
SELECT COUNT(*) as total_records FROM test_hdfs;

-- Show sample data
SELECT * FROM test_hdfs LIMIT 10;

-- Show data grouped by partition
SELECT partition, COUNT(*) as record_count FROM test_hdfs GROUP BY partition;

-- Show the location of the table
SHOW TBLPROPERTIES test_hdfs;

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

if grep -q "test_hdfs" /tmp/result.log; then
    log "✅ SUCCESS: Hive table created successfully"
else
    log "❌ ERROR: Hive table not found"
fi

if grep -q "testhive" /tmp/result.log; then
    log "✅ SUCCESS: Hive database created successfully"
else
    log "❌ ERROR: Hive database not found"
fi

log "Querying records from test_hdfs table"
docker exec hive-server beeline -u "jdbc:hive2://hive-server:10000" -e "
USE testhive;
SELECT 'Total Records:' as info, COUNT(*) as count FROM test_hdfs
UNION ALL
SELECT 'Sample Records:', '' as count;
SELECT f1, partition FROM test_hdfs LIMIT 10;
"

