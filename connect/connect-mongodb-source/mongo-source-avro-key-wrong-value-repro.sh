#!/bin/bash
set -e

# Repro 2/3 for the fully-managed MongoDbAtlasSource "ReplaceField$Key" / "Only Struct objects
# supported for [field replacement], found: java.lang.String" incident.
#
# This pass runs WITHOUT any SMT, using a valid Avro field name "_id" in output.schema.key (this is
# actually the connector's own DEFAULT value for output.schema.key), with AVRO key output.
#
# Result: the task stays RUNNING, but the emitted key is NOT the document's real _id. It is the
# change-stream event's own top-level _id, i.e. the change-stream RESUME TOKEN:
#   Key:{"_id":"{\"_data\": \"826ABA2C2E...\"}"}
# The schema-based key builder matches field names against the top-level change-stream event
# (which has its own "_id" = resume token), not against the nested "documentKey._id" - there is no
# dotted-path traversal into documentKey.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.avro-key-repro.yml"

log "Initialize MongoDB replica set"
playground container exec --container mongodb --command "mongosh --eval 'rs.initiate({_id: \"myuser\", members:[{_id: 0, host: \"mongodb:27017\"}]})'"

sleep 5

log "Create a user profile"
playground container exec --container mongodb --command "mongosh" << EOF
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

log "🧪 Creating MongoDB source connector with AVRO key output.schema.key field named '_id' (connector default), WITHOUT any SMT"
playground connector create-or-update --connector mongodb-source-avro-key-wrong-value-repro << EOF
{
     "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
     "tasks.max" : "1",
     "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
     "database":"inventory",
     "collection":"customers",
     "topic.prefix":"mongo",
     "output.format.value": "schema",
     "output.schema.infer.value": "true",
     "output.format.key": "schema",
     "output.schema.key": "{ \"type\": \"record\", \"name\": \"keySchema\", \"fields\": [{ \"name\": \"_id\", \"type\": \"string\"}]}",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF

sleep 5

log "Insert a record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 2, first_name : 'Robert', last_name : 'DeNiro', email : 'robert@example.com' }
]);
EOF

sleep 5

log "🔎 Expected result: task RUNNING, but Key is the change-stream resume token, NOT the document _id (2)"
playground connector status --connector mongodb-source-avro-key-wrong-value-repro
playground topic consume --topic mongo.inventory.customers --min-expected-messages 1 --timeout 60
