#!/bin/bash
set -e

# Repro 6/6 for the Getir / Zendesk #365409 MongoDB Atlas Source key issue.
#
# Tests the AVRO-key/output.schema.key/ReplaceField$Key SMT workaround (suggested to the customer)
# combined with EVERY setting from the customer's original productlocation-source config, not just
# the tombstone-related subset tested in mongo-source-avro-key-tombstone-exact-config-repro.sh:
#   - copy.existing: true   (was "false" in the earlier SMT-workaround test)
#   - heartbeat.interval.ms: 10000  (was unset/default 0)
#   - producer.override.compression.type: lz4  (was unset)
#   - publish.full.document.only / publish.full.document.only.tombstone.on.delete / change.stream.document.key.as.key: true
#   - output.data.format=AVRO / output.key.format=AVRO -> output.format.key=schema
#   - output.schema.key field "documentKey._id" + ReplaceField$Key SMT renaming it to "_id"
#
# Exercises all three code paths: a PRE-EXISTING document (via copy.existing), a LIVE INSERT, and a
# LIVE DELETE (tombstone, since publish.full.document.only.tombstone.on.delete=true) - to check
# whether the SMT workaround keeps all three keys consistent once copy.existing is also enabled.

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

log "Insert a PRE-EXISTING record BEFORE the connector starts (will be picked up via copy.existing=true)"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

sleep 2

log "🧪 Creating MongoDB source connector with the FULL original config (copy.existing, heartbeat.interval.ms, producer.override.compression.type, tombstone settings) PLUS the AVRO-key/documentKey._id schema + ReplaceField\$Key SMT workaround"
playground connector create-or-update --connector mongodb-source-avro-key-smt-full-original-repro << EOF
{
     "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
     "tasks.max" : "1",
     "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
     "database":"inventory",
     "collection":"customers",
     "topic.prefix":"mongo",
     "topic.separator": ".",
     "copy.existing": "true",
     "errors.tolerance": "none",
     "poll.await.time.ms": "5000",
     "poll.max.batch.size": "1000",
     "heartbeat.interval.ms": "10000",
     "publish.full.document.only": "true",
     "publish.full.document.only.tombstone.on.delete": "true",
     "change.stream.document.key.as.key": "true",
     "producer.override.compression.type": "lz4",
     "output.format.value": "schema",
     "output.schema.infer.value": "true",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "output.format.key": "schema",
     "output.schema.key": "{ \"type\": \"record\", \"name\": \"keySchema\", \"fields\": [{ \"name\": \"documentKey._id\", \"type\": \"string\"}]}",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081",
     "transforms": "renameKey",
     "transforms.renameKey.type": "io.confluent.connect.transforms.ReplaceField\$Key",
     "transforms.renameKey.renames": "documentKey._id:_id"
}
EOF

sleep 10

log "🔎 Status after copy.existing pass + start of change stream"
playground connector status --connector mongodb-source-avro-key-smt-full-original-repro

log "Insert a LIVE record (via the change stream)"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.insert([
{ _id : 2, first_name : 'Robert', last_name : 'DeNiro', email : 'robert@example.com' }
]);
EOF

sleep 8

log "Delete _id=1 (LIVE DELETE -> tombstone, since publish.full.document.only.tombstone.on.delete=true)"
playground container exec --container mongodb --command "mongosh" << EOF
use inventory
db.customers.deleteOne({ _id : 1 });
EOF

sleep 8

log "🔎 Final status"
playground connector status --connector mongodb-source-avro-key-smt-full-original-repro

log "🔎 Comparing the key shape/value for: (1) copy.existing doc _id=1, (2) live insert _id=2, (3) live delete/tombstone of _id=1"
playground topic consume --topic mongo.inventory.customers --min-expected-messages 2 --timeout 60
