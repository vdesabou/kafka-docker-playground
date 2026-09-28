#!/bin/bash
set -e

# Repro 3/3 for the fully-managed MongoDbAtlasSource "ReplaceField$Key" / "Only Struct objects
# supported for [field replacement], found: java.lang.String" incident.
#
# This pass restores the customer's exact workaround: output.schema.key with field "documentKey._id"
# (invalid Avro name, see mongo-source-avro-key-invalid-schema-repro.sh) PLUS the ReplaceField$Key SMT
# renaming documentKey._id -> _id, with AVRO key output.
#
# Result (on the self-managed/OSS connector, locally): the task stays RUNNING and produces the
# correct key, e.g. Key:{"_id":"3"} - the SMT receives a Struct (not a String) and successfully
# renames the field before AvroConverter ever sees the illegal "documentKey._id" name.
#
# This is the OPPOSITE of what the customer observed on the fully-managed connector
# (DataException: Only Struct objects supported for [field replacement], found: java.lang.String),
# which means the fully-managed MongoDbAtlasSource connector must be collapsing the key to a plain
# String earlier in its pipeline than this OSS connector does - that behavioral difference, not the
# SMT itself, is the actual defect to chase.

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

log "🧪 Creating MongoDB source connector with AVRO key output.schema.key field 'documentKey._id' PLUS ReplaceField\$Key SMT (documentKey._id -> _id)"
playground connector create-or-update --connector mongodb-source-avro-key-smt-workaround-repro << EOF
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
     "output.schema.key": "{ \"type\": \"record\", \"name\": \"keySchema\", \"fields\": [{ \"name\": \"documentKey._id\", \"type\": \"string\"}]}",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081",
     "transforms": "renameKey",
     "transforms.renameKey.type": "io.confluent.connect.transforms.ReplaceField\$Key",
     "transforms.renameKey.renames": "documentKey._id:_id"
}
EOF

sleep 5

log "Insert a record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 3, first_name : 'Ann', last_name : 'Test', email : 'ann@example.com' }
]);
EOF

sleep 8

log "🔎 Expected result: task RUNNING, Key is the real document _id (3), e.g. Key:{\"_id\":\"3\"}"
playground connector status --connector mongodb-source-avro-key-smt-workaround-repro
playground topic consume --topic mongo.inventory.customers --min-expected-messages 1 --timeout 60
