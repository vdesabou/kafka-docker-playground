#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-106537-multiple-events-in-same-topic.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongo --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

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
                    "pipeline":"[{\"$match\": {\"ns.coll\": {\"$regex\": \"^(customers|product)$\"}}}]",
                    "topic.namespace.map": "{\"*\": \"all-types\"}",
                    "publish.full.document.only": "true",
                    "output.format.value": "schema",
                    "output.schema.infer.value": "true",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.value.subject.name.strategy": "io.confluent.kafka.serializers.subject.TopicRecordNameStrategy"
          }' \
     http://localhost:8083/connectors/mongodb-source/config | jq .

sleep 5

log "Insert a record in customers"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.insert([ 
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "Insert a record in product"
docker exec -i mongodb mongosh << EOF
use inventory
db.product.insert([
{ _id : 1, product : 'My product' }
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

log "Verifying topic all-types"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic all-types --from-beginning --max-messages 2

# {"_id":{"int":1},"email":{"string":"thebob@example.com"},"first_name":{"string":"Bob"},"last_name":{"string":"Hopper"}}
# {"_id":{"int":1},"product":{"string":"My product"}}

# record name is "default":
# curl --request GET \
#   --url http://localhost:8081/subjects/all-types-default/versions
# [1,2]