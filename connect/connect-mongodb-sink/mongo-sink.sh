#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

dump_mongodb_diagnostics() {
    echo "=== DIAGNOSTIC: host kernel/OS (checking applicability of https://jira.mongodb.org/browse/SERVER-121912, kernel 6.19+) ==="
    uname -a 2>&1 || true
    cat /etc/os-release 2>&1 || true
    echo
    echo "=== DIAGNOSTIC: mongodb container state (docker inspect) ==="
    docker inspect mongodb --format '{{json .State}}' 2>&1 || true
    echo
    echo "=== DIAGNOSTIC: mongodb container logs (last 200 lines) ==="
    docker logs --tail 200 mongodb 2>&1 || true
    echo
    echo "=== DIAGNOSTIC: dmesg (oom/kill-related lines) ==="
    if command -v dmesg >/dev/null 2>&1; then
        (dmesg 2>&1 || sudo dmesg 2>&1 || true) | grep -iE "kill|oom" | tail -50
    else
        echo "dmesg not available on this host"
    fi
    echo
    echo "=== DIAGNOSTIC: host memory ==="
    if command -v free >/dev/null 2>&1; then
        free -h 2>&1 || true
    else
        vm_stat 2>&1 || echo "no memory stats command available"
    fi
}
trap dump_mongodb_diagnostics EXIT

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Initialize MongoDB replica set"
playground container exec --container mongodb --command "mongosh --eval 'rs.initiate({_id: \"myuser\", members:[{_id: 0, host: \"mongodb:27017\"}]})'"

sleep 5

log "Create a user profile"
playground container exec --container mongodb --command "mongosh" << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

log "Creating MongoDB sink connector"
playground connector create-or-update --connector mongodb-sink  << EOF
{
    "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
    "tasks.max" : "1",
    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
    "database":"inventory",
    "collection":"customers",
    "topics":"orders"
}
EOF

sleep 10

log "View record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.find().pretty();
EOF

playground container exec --container mongodb --command "mongosh" << EOF > output.txt
use inventory
db.customers.find().pretty();
EOF
grep "foo" output.txt
rm output.txt