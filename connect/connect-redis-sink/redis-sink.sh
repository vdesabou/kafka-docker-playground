#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic users"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic users --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

echo "Creating Redis sink connector"
docker exec connect \
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

echo "Verify data is in Redis"
docker exec -it redis redis-cli COMMAND GETKEYS "MSET" "key1" "value1" "key2" "value2" "key3" "value3"
docker exec -it redis redis-cli COMMAND GETKEYS "MSET" "__kafka.offset.users.0" "{\"topic\":\"users\",\"partition\":0,\"offset\":2}"