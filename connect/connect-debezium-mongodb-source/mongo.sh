#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Initialize MongoDB replica set"
docker exec -it mongodb mongo --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

echo "Create a user profile"
docker exec -i mongodb mongo << EOF
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

echo "Insert a record"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

echo "View record"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF

echo "Creating Debezium MongoDB source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
                    "tasks.max" : "1",
                    "mongodb.hosts" : "debezium/mongodb:27017",
                    "mongodb.name" : "dbserver1",
                    "mongodb.user" : "debezium",
                    "mongodb.password" : "dbz",
                    "database.history.kafka.bootstrap.servers" : "broker:9092"
          }' \
     http://localhost:8083/connectors/debezium-mongodb-source/config | jq .


sleep 5

echo "Verifying topic dbserver1.inventory.customers"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic dbserver1.inventory.customers --from-beginning --max-messages 1
