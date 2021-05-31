#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.2.2.4.yml"


log "Sending messages to topic hbase-test"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic hbase-test --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

log "Creating HBase sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/hbase-sink/config | jq .

log "Verify data is in HBase:"
docker exec -i hbase hbase shell > /tmp/result.log <<-EOF
scan 'example_table'
EOF
cat /tmp/result.log
grep "key1" /tmp/result.log | grep "value=value1"
grep "key2" /tmp/result.log | grep "value=value2"
grep "key3" /tmp/result.log | grep "value=value3"