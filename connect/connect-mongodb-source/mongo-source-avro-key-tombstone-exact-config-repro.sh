#!/bin/bash
set -e

# Repro 4/4 for the fully-managed MongoDbAtlasSource "ReplaceField$Key" / "Only Struct objects
# supported for [field replacement], found: java.lang.String" incident (Getir / Zendesk #365409).
#
# Unlike the previous 3 repro scripts, this one exactly matches the customer's connector settings
# confirmed from the Connect REST config dump on the ticket (lcc-o3q68xp) plus their reported
# config excerpt on lcc-w7jm005:
#   - publish.full.document.only: true
#   - publish.full.document.only.tombstone.on.delete: true
#   - change.stream.document.key.as.key: true
#   - output.data.format=AVRO / output.key.format=AVRO -> output.format.key=schema
#   - output.schema.key field "documentKey._id" + ReplaceField$Key SMT renaming it to "_id"
#
# Crucially, this script exercises BOTH an INSERT and a DELETE (which becomes a tombstone because
# publish.full.document.only.tombstone.on.delete=true). Support's own hypothesis was that insert/update
# and tombstone/delete events go through different code paths in the connector, producing an
# inconsistent key structure between them - the 3 previous repro scripts only ever tested inserts,
# never a delete, so they never exercised the actual code path the customer is hitting.

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

log "🧪 Creating MongoDB source connector matching the customer's exact settings (publish.full.document.only, tombstone.on.delete, change.stream.document.key.as.key, AVRO key + documentKey._id schema + ReplaceField\$Key SMT)"
playground connector create-or-update --connector mongodb-source-avro-key-tombstone-repro << EOF
{
     "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
     "tasks.max" : "1",
     "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
     "database":"inventory",
     "collection":"customers",
     "topic.prefix":"mongo",
     "topic.separator": ".",
     "change.stream.document.key.as.key": "true",
     "change.stream.full.document": "default",
     "change.stream.full.document.before.change": "default",
     "publish.full.document.only": "true",
     "publish.full.document.only.tombstone.on.delete": "true",
     "copy.existing": "false",
     "output.format.value": "schema",
     "output.schema.infer.value": "true",
     "output.format.key": "schema",
     "output.schema.key": "{ \"type\": \"record\", \"name\": \"keySchema\", \"fields\": [{ \"name\": \"documentKey._id\", \"type\": \"string\"}]}",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081",
     "transforms": "renameKey",
     "transforms.renameKey.type": "io.confluent.connect.transforms.ReplaceField\$Key",
     "transforms.renameKey.renames": "documentKey._id:_id",
     "errors.tolerance": "none"
}
EOF

sleep 5

log "Insert a record (exercises the INSERT code path)"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

sleep 8

log "🔎 Status/key after INSERT"
playground connector status --connector mongodb-source-avro-key-tombstone-repro

log "Delete the record (exercises the DELETE / tombstone code path, since publish.full.document.only.tombstone.on.delete=true)"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.deleteOne({ _id : 1 });
EOF

sleep 8

log "🔎 Expected point of interest: does the task FAIL here (on the delete/tombstone) with DataException: Only Struct objects supported... found: java.lang.String, even though the insert above succeeded?"
playground connector status --connector mongodb-source-avro-key-tombstone-repro

log "🔎 Comparing INSERT key vs DELETE/tombstone key on the topic"
playground topic consume --topic mongo.inventory.customers --min-expected-messages 1 --timeout 60
