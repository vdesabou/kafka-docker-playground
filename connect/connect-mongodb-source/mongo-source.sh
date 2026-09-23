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

log "Creating MongoDB source connector"
playground connector create-or-update --connector mongodb-source  << EOF
{
     "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
     "tasks.max" : "1",
     "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
     "database":"inventory",
     "collection":"customers",
     "topic.prefix":"mongo",
     "output.format.value": "schema",
     "output.schema.infer.value": "true"
}
EOF

sleep 5

# using pipeline:

# {
#     "connection.uri": "mongodb://myuser:mypassword@mongodb:27017",
#     "connector.class": "com.mongodb.kafka.connect.MongoSourceConnector",
#     "pipeline":"[{\"$match\": {\"ns.coll\": {\"$regex\": \"^(customers|goals)$\"}}}]",
#     "database":"inventory",
#     "tasks.max": "1",
#     "topic.prefix": "mongo"
# }

log "Insert a record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

# log "Update a record"
# playground container exec -i mongodb mongosh << EOF
# use inventory
# db.customers.updateOne(
#      { _id: 1 },
#      {
#            \$set: {
#                 email : "thebob2@example.com"
#                 }
#      }
     
# );
# EOF

log "View record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.find().pretty();
EOF

sleep 5

log "Verifying topic mongo.inventory.customers"
playground topic consume --topic mongo.inventory.customers --min-expected-messages 1 --timeout 60
