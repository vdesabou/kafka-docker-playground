#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "0.0.6"
then
     logwarn "minimal supported connector version is 0.0.7 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

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
# the connector writes to redis database 1 by default (redis.database)
playground container exec --container redis --command "redis-cli -n 1 KEYS '*'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "__kafka.offset.users.0" /tmp/result.log
playground container exec --container redis --command "redis-cli -n 1 GET key1" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log
