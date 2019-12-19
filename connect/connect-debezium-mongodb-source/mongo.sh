#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mInitialize MongoDB replica set\033[0m"
docker exec -it mongodb mongo --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

echo -e "\033[0;33mCreate a user profile\033[0m"
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

echo -e "\033[0;33mInsert a record\033[0m"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

echo -e "\033[0;33mView record\033[0m"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF

echo -e "\033[0;33mCreating Debezium MongoDB source connector\033[0m"
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

echo -e "\033[0;33mVerifying topic dbserver1.inventory.customers\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic dbserver1.inventory.customers --from-beginning --max-messages 1
