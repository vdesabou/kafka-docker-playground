#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic users"
playground topic produce -t users --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

log "Creating Redis sink connector"
playground connector create-or-update --connector redis-sink  << EOF
{
     "connector.class": "com.github.jcustenborder.kafka.connect.redis.RedisSinkConnector",
     "redis.hosts": "redis:6379",
     "tasks.max": "1",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.storage.StringConverter",
     "topics": "users"
}
EOF

sleep 10

log "Verify data is in Redis"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "key1" "value1" "key2" "value2" "key3" "value3"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "__kafka.offset.users.0" "{\"topic\":\"users\",\"partition\":0,\"offset\":2}" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "__kafka.offset.users.0" /tmp/result.log