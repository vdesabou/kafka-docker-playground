#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89605-not-producing-messages-although-in-a-running-state.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongo --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
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

# https://docs.mongodb.com/kafka-connector/current/troubleshooting/recover-from-invalid-resume-token/#std-label-invalid-resume-token-cause
# no more messages in topic __mongodb_heartbeats due to filter smt
log "Creating MongoDB source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "database":"inventory",
                    "collection":"customers",
                    "topic.prefix":"mongo",
                    "offset.partition.name": "my-offset-partition-name-smt",
                    "heartbeat.interval.ms": "3000",
                    "transforms": "filterHeartbeats",
                    "transforms.filterHeartbeats.type": "org.apache.kafka.connect.transforms.Filter",
                    "transforms.filterHeartbeats.predicate": "isHeartbeat",
                    "predicates": "isHeartbeat",
                    "predicates.isHeartbeat.pattern": "__mongodb_heartbeats",
                    "predicates.isHeartbeat.type": "org.apache.kafka.connect.transforms.predicates.TopicNameMatches"
          }' \
     http://localhost:8083/connectors/mongodb-source-smt/config | jq .


sleep 5



log "Insert a record"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF

sleep 5

log "Verifying topic mongo.inventory.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mongo.inventory.customers --from-beginning --max-messages 1

log "Checking connect-offsets"
docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true

