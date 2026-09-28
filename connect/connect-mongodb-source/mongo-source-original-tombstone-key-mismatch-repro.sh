#!/bin/bash
set -e

# Repro 5/5 for the Getir / Zendesk #365409 MongoDB Atlas Source key-mismatch issue.
#
# This is the ORIGINAL reported bug (before any AVRO-key/ReplaceField$Key workaround was
# suggested): "if you delete a document in a MongoDB collection, the key of the generated
# tombstone doesn't match the existing key". This is a mismatch, not a crash.
#
# Config below is translated 1:1 from the customer's actual mongodb-productlocation-source
# connector config:
#   {"output.data.format": "AVRO", "output.key.format": "JSON", "copy.existing": "true",
#    "publish.full.document.only": "true", "publish.full.document.only.tombstone.on.delete": "true",
#    "change.stream.document.key.as.key": "true", "producer.override.compression.type": "lz4",
#    "heartbeat.interval.ms": "10000", "errors.tolerance": "none", ...}
#
# Per Support's own diagnosis (Zendesk #365409): output.data.format=AVRO forces output.format.key
# to "schema" regardless of output.key.format, while key.converter stays JsonConverter (confirmed
# from the real Connect REST config dump on lcc-o3q68xp - key.converter was
# org.apache.kafka.connect.json.JsonConverter even with output.data.format=AVRO). No output.schema.key
# override was set by the customer at this stage, so it uses the connector's own default
# ({"type":"record","name":"keySchema","fields":[{"name":"_id","type":"string"}]}).
#
# This script exercises THREE distinct code paths and compares their key shape/value:
#   1. a PRE-EXISTING document, picked up via copy.existing=true (initial collection scan)
#   2. a LIVE INSERT (via the change stream)
#   3. a LIVE DELETE, which becomes a tombstone because publish.full.document.only.tombstone.on.delete=true

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

log "🧪 Creating MongoDB source connector matching the customer's ORIGINAL productlocation-source config (output.data.format=AVRO / output.key.format=JSON, copy.existing=true, publish.full.document.only + tombstone.on.delete, change.stream.document.key.as.key), NO output.schema.key override, NO SMT"
playground connector create-or-update --connector mongodb-source-original-tombstone-repro << EOF
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
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "key.converter.schemas.enable": "false"
}
EOF

sleep 10

log "🔎 Status after copy.existing pass + start of change stream"
playground connector status --connector mongodb-source-original-tombstone-repro

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
playground connector status --connector mongodb-source-original-tombstone-repro

log "🔎 Comparing the key shape/value for: (1) copy.existing doc _id=1, (2) live insert _id=2, (3) live delete/tombstone of _id=1"
playground topic consume --topic mongo.inventory.customers --min-expected-messages 2 --timeout 60
