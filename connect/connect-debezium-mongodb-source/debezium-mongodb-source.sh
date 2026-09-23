#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.4.99"
then
     logwarn "minimal supported connector version is 2.5.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

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
playground container exec --container mongodb --command "mongosh --eval 'rs.initiate({_id: \"debezium\", members:[{_id: 0, host: \"mongodb:27017\"}]})'"

sleep 5

log "Create a user profile"
playground container exec --container mongodb --command "mongosh" << EOF
use admin
db.createUser(
{
user: "debezium",
pwd: "dbz",
roles: ["dbOwner"]
}
)
EOF

sleep 2

log "Insert a record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.find().pretty();
EOF

log "Creating Debezium MongoDB source connector"
playground connector create-or-update --connector debezium-mongodb-source  << EOF
{
    "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
    "tasks.max" : "1",
    "_comment": "old version before 2.4.x",
    "mongodb.hosts": "debezium/mongodb:27017",
    "_comment": "new version since 2.4.x",
    "mongodb.connection.string": "mongodb://mongodb:27017/?replicaSet=debezium",

    "_comment": "old version before 2.x",
    "mongodb.name": "dbserver1",
    "_comment": "new version since 2.x",
    "topic.prefix": "dbserver1",

    "mongodb.user" : "debezium",
    "mongodb.password" : "dbz",

    "_comment:": "remove _ to use ExtractNewRecordState smt",
    "_transforms": "unwrap",
    "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF


sleep 5

log "Verifying topic dbserver1.inventory.customers"
playground topic consume --topic dbserver1.inventory.customers --min-expected-messages 1 --timeout 60
