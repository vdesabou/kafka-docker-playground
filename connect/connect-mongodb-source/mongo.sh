#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mInitialize MongoDB replica set\033[0m"
docker exec -it mongodb mongo --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

echo -e "\033[0;33mCreate a user profile\033[0m"
docker exec -i mongodb mongo << EOF
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

echo -e "\033[0;33mCreating MongoDB source connector\033[0m"
docker exec connect \
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

echo -e "\033[0;33mInsert a record\033[0m"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

echo -e "\033[0;33mView record\033[0m"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF

sleep 5

echo -e "\033[0;33mVerifying topic mongo.inventory.customers\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic mongo.inventory.customers --from-beginning --max-messages 1
