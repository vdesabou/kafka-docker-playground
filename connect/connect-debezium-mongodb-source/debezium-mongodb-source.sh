#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongo --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

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
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
               "tasks.max" : "1",
               "mongodb.hosts" : "debezium/mongodb:27017",
               "mongodb.name" : "dbserver1",
               "mongodb.user" : "debezium",
               "mongodb.password" : "dbz"
          }' \
     http://localhost:8083/connectors/debezium-mongodb-source/config | jq .


sleep 5

log "Verifying topic dbserver1.inventory.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1.inventory.customers --from-beginning --max-messages 1
