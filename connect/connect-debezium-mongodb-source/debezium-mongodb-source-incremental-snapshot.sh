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

    "signal.data.collection": "inventory.debezium_signal",
    "collection.include.list": "inventory.customers,inventory.debezium_signal",

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


log "Insert a record in new collection customers2"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers2.insert([
{ _id : 1010, first_name : 'John', last_name : 'Greek', email : 'greek@example.com' }
]);
EOF

log "Updating connector to include new collection"
playground connector create-or-update --connector debezium-mongodb-source << EOF
{
    "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
    "tasks.max" : "1",
    "mongodb.hosts" : "debezium/mongodb:27017",

    "_comment": "old version before 2.x",
    "mongodb.name": "dbserver1",
    "_comment": "new version since 2.x",
    "topic.prefix": "dbserver1",

    "signal.data.collection": "inventory.debezium_signal",
    "collection.include.list": "inventory.customers,inventory.debezium_signal,inventory.customers2",

    "mongodb.user" : "debezium",
    "mongodb.password" : "dbz",

    "_comment:": "remove _ to use ExtractNewRecordState smt",
    "_transforms": "unwrap",
    "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF


log "Insert another record in new collection customers2"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers2.insert([
{ _id : 1011, first_name : 'Peter', last_name : 'Pan', email : 'pan@example.com' }
]);
EOF

# FIXTHIS: we can see 2 records here, not sure why?
log "Verifying topic dbserver1.inventory.customers2 : there will be only the new record"
playground topic consume --topic dbserver1.inventory.customers2 --min-expected-messages 1 --timeout 60


log "Trigger Ad hoc snapshot"
docker exec -i mongodb mongosh << EOF
use inventory
db.debezium_signal.insert({type : 'execute-snapshot', data : { 'data-collections' : [ 'inventory.customer2'], type: 'incremental'} });
EOF


sleep 5

log "Verifying topic server1.testDB.dbo.customers2: it should have all records"
playground topic consume --topic dbserver1.inventory.customers2 --min-expected-messages 2 --timeout 60
