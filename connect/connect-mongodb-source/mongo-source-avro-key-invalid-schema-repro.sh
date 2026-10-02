#!/bin/bash
set -e

# Repro 1/3 for the fully-managed MongoDbAtlasSource "ReplaceField$Key" / "Only Struct objects
# supported for [field replacement], found: java.lang.String" incident.
#
# This pass runs WITHOUT any SMT, using the exact output.schema.key from the previous incident's
# suggested workaround (field named "documentKey._id"), with AVRO key output (output.format.key=schema
# + key.converter=AvroConverter, mirroring output.data.format=AVRO/output.key.format=AVRO on the
# fully-managed connector).
#
# Result: the task fails on the VERY FIRST record, before any SMT even runs:
#   org.apache.avro.SchemaParseException: Illegal character in: documentKey._id
#     at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:99)
# Avro record field names cannot contain "." - so this output.schema.key is invalid for AVRO
# key output regardless of whether the ReplaceField$Key SMT is present.

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

log "🧪 Creating MongoDB source connector with AVRO key output.schema.key field named 'documentKey._id', WITHOUT any SMT"
playground connector create-or-update --connector mongodb-source-avro-key-invalid-schema-repro << EOF
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
     "key.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF

sleep 5

log "Insert a record"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

sleep 10

log "🔎 Expected result: task FAILED with org.apache.avro.SchemaParseException: Illegal character in: documentKey._id"
playground connector status --connector mongodb-source-avro-key-invalid-schema-repro
