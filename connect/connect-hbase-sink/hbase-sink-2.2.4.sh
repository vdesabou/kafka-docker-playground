#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "5.9.0"; then
     log "Hbase does not support JDK 11, see https://hbase.apache.org/book.html#java"
     # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/907
     exit 107
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.2.2.4.yml"


log "Sending messages to topic hbase-test"
playground topic produce -t hbase-test --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

log "Creating HBase sink connector"
playground connector create-or-update --connector hbase-sink  << EOF
{
     "connector.class": "io.confluent.connect.hbase.HBaseSinkConnector",
     "tasks.max": "1",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor":1,
     "hbase.zookeeper.quorum": "hbase",
     "hbase.zookeeper.property.clientPort": "2181",
     "auto.create.tables": "true",
     "auto.create.column.families": "false",
     "table.name.format": "example_table",
     "topics": "hbase-test"
}
EOF

sleep 10

log "Verify data is in HBase:"
docker exec -i hbase hbase shell > /tmp/result.log  2>&1 <<-EOF
scan 'example_table'
EOF
cat /tmp/result.log
grep "key1" /tmp/result.log | grep "value=value1"
grep "key2" /tmp/result.log | grep "value=value2"
grep "key3" /tmp/result.log | grep "value=value3"