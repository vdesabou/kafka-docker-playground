#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mongo-sink-repro-sharding.yml"

MAX_WAIT=40
log "⌛ Waiting up to $MAX_WAIT seconds for MongoDB to start"
until $(curl --output /dev/null --silent --fail localhost:27017); do printf '.'; sleep 5; if [[ $var -eq ${MAX_WAIT} ]] ; then exit 1; fi; var=$((var+1)); done
log "MongoDB DB has started!"

log "Create a user profile"
docker exec -i mongodb-sharded mongosh << EOF
use admin
db.createUser(
  {
    user: "myuser",
    pwd: "mypassword",
    roles: ["dbOwner"]
  }
)
EOF

# Example of upserting in a sharded collection
# https://docs.mongodb.com/kafka-connector/current/kafka-sink-postprocessors/#replaceonebusinesskeystrategy-example
log "Create a sharded collection"
docker exec -i mongodb-sharded mongosh << EOF
use inventory
db.createCollection("products")
db.collection.createIndex({ "id": 1, "product": 1}, { unique: true })
sh.enableSharding("inventory")
sh.shardCollection("inventory.products", { "id": 1, "product": 1} )
EOF

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"id","type":"string"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": "111", "product": "foo", "quantity": 100, "price": 50}
{"id": "222", "product": "bar", "quantity": 100, "price": 50}
EOF

log "Creating MongoDB sink connector with sharded collection"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "topics":"orders",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb-sharded:27017",
                    "database":"inventory",
                    "collection":"products",
                    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.PartialValueStrategy",
                    "document.id.strategy.partial.value.projection.list": "id,product",
                    "document.id.strategy.partial.value.projection.type": "AllowList",
                    "writemodel.strategy": "com.mongodb.kafka.connect.sink.writemodel.strategy.ReplaceOneBusinessKeyStrategy"
          }' \
     http://localhost:8083/connectors/mongodb-sharded-sink/config | jq .

log "Waiting 10s for the connector to start and process extisting records"
sleep 10

log "Verify records have been upserted"
docker exec -i mongodb-sharded mongosh << EOF
use inventory;
db.products.find().pretty();
EOF

docker exec -i mongodb-sharded mongosh << EOF > output.txt
use inventory;
db.products.find().pretty();
EOF
grep "foo" output.txt
rm output.txt

# Reproducer of upsert in a sharded collection without actual shard filter
log "Create a sharded collection"
docker exec -i mongodb-sharded mongosh << EOF
use inventory
db.createCollection("products-with-key")
db.collection.createIndex({ "id": 1, "product": 1}, { unique: true })
sh.enableSharding("inventory")
sh.shardCollection("inventory.products-with-key", { "id": 1, "product": 1} )
EOF

log "Sending messages to topic orders-with-key with _id in the message's key"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders-with-key --property key.schema='{"type":"record","name":"myrecordkey","fields":[{"name":"_id","type":"string"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"id","type":"string"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"_id": "111"}|{"id": "111", "product": "foo", "quantity": 100, "price": 50}
{"_id": "222"}|{"id": "222", "product": "bar", "quantity": 100, "price": 50}
EOF

log "Creating MongoDB sink connector with sharded collection and _id in the message's key"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "topics":"orders-with-key",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb-sharded:27017",
                    "database":"inventory",
                    "collection":"products-with-key",
                    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.ProvidedInKeyStrategy",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081"

          }' \
     http://localhost:8083/connectors/mongodb-sharded-sink-with-key/config | jq .

log "Waiting 10s for the connector to start and process extisting records"
sleep 10

log "Verify connector fails to upsert in a sharded collection"
curl -s http://localhost:8083/connectors/mongodb-sharded-sink-with-key/status | grep -o "Failed to target upsert by query :: could not extract exact shard key"
