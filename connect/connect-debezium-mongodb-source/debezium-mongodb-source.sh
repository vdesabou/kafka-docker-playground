#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh << EOF
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
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF

log "Creating Debezium MongoDB source connector"
playground connector create-or-update --connector debezium-mongodb-source << EOF
{
               "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
               "tasks.max" : "1",
               "mongodb.hosts" : "debezium/mongodb:27017",

               "_comment": "old version before 2.x",
               "mongodb.name": "dbserver1",
               "_comment": "new version since 2.x",
               "topic.prefix": "dbserver1",

               "mongodb.user" : "debezium",
               "mongodb.password" : "dbz"
          }
EOF


sleep 5

log "Verifying topic dbserver1.inventory.customers"
playground topic consume --topic dbserver1.inventory.customers --min-expected-messages 1 --timeout 60
