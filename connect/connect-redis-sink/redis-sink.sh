#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic users"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic users --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

log "Creating Redis sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.github.jcustenborder.kafka.connect.redis.RedisSinkConnector",
                    "redis.hosts": "redis:6379",
                    "tasks.max": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "topics": "users"
          }' \
     http://localhost:8083/connectors/redis-sink/config | jq .

sleep 10

log "Verify data is in Redis"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "key1" "value1" "key2" "value2" "key3" "value3"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "__kafka.offset.users.0" "{\"topic\":\"users\",\"partition\":0,\"offset\":2}" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "__kafka.offset.users.0" /tmp/result.log