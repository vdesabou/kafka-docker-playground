#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh << EOF
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
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "database":"inventory",
                    "collection":"customers",
                    "topic.prefix":"mongo"
          }' \
     http://localhost:8083/connectors/mongodb-source/config | jq .

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
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

# log "Update a record"
# docker exec -i mongodb mongosh << EOF
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
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF

sleep 5

log "Verifying topic mongo.inventory.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mongo.inventory.customers --from-beginning --max-messages 1
