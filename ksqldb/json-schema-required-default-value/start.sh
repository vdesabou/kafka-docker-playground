#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Create a topic named play-json-single"
playground topic create --topic play-json-single --nb-partitions 1

log "Create a topic named play-json-single-required"
playground topic create --topic play-json-single-required --nb-partitions 1

log "Create a topic named play-json-single-default"
playground topic create --topic play-json-single-default --nb-partitions 1

log "Register the JSON Schema with a single string field"
playground schema register --subject play-json-single-value << 'EOF'
{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string"}},"title":"SampleRecord","type":"object"}
EOF
# {
#   "$id": "http://example.com/myURI.schema.json",
#   "$schema": "http://json-schema.org/draft-07/schema#",
#   "description": "Sample schema to help you get started.",
#   "properties": {
#     "stringField": {
#       "type": "string"
#     }
#   },
#   "title": "SampleRecord",
#   "type": "object"
# }

log "Register the JSON Schema with a single string field, but field is marked as required"
playground schema register --subject play-json-single-required-value << 'EOF'
{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string"}},"required":["stringField"],"title":"SampleRecord","type":"object"}
EOF
 # {
 #   "$id": "http://example.com/myURI.schema.json",
 #   "$schema": "http://json-schema.org/draft-07/schema#",
 #   "description": "Sample schema to help you get started.",
 #   "properties": {
 #     "stringField": {
 #       "type": "string"
 #     }
 #   },
 #   "required": [
 #     "stringField"
 #   ],
 #   "title": "SampleRecord",
 #   "type": "object"
 # }

log "Register the JSON Schema with a single string field, but field is marked as required + field also has default value"
playground schema register --subject play-json-single-default-value << 'EOF'
{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string","default":"test"}},"required":["stringField"],"title":"SampleRecord","type":"object"}
EOF
  # {
  #   "$id": "http://example.com/myURI.schema.json",
  #   "$schema": "http://json-schema.org/draft-07/schema#",
  #   "description": "Sample schema to help you get started.",
  #   "properties": {
  #     "stringField": {
  #       "type": "string",
  #       "default": "test"
  #     }
  #   },"required": [
  #     "stringField"
  #   ],
  #   "title": "SampleRecord",
  #   "type": "object"
  # }

# a record that does not match the JSON Schema is refused by the serializer (JSON Schema validation): it never reaches the topic
function expect_rejected () {
  local topic="$1" value="$2" schema="$3"
  set +e
  playground topic produce -t "$topic" --nb-messages 1 --forced-value "$value" <<< "$schema"
  local rc=$?
  set -e
  if [ $rc -eq 0 ]
  then
    logerror "❌ $value should have been refused by the JSON Schema of topic $topic"
    exit 1
  fi
  log "✅ $value refused by the JSON Schema of topic $topic, as expected"
}

log "Produce records to the topics"
playground topic produce -t play-json-single --nb-messages 1 --forced-value '{"stringField":"foo"}' << 'EOF'
{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string"}},"title":"SampleRecord","type":"object"}
EOF

playground topic produce -t play-json-single-required --nb-messages 1 --forced-value '{"stringField":"foo"}' << 'EOF'
{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string"}},"required":["stringField"],"title":"SampleRecord","type":"object"}
EOF
# null is not a string (required or not)
expect_rejected play-json-single-required '{"stringField":null}' '{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string"}},"required":["stringField"],"title":"SampleRecord","type":"object"}'

playground topic produce -t play-json-single-default --nb-messages 1 --forced-value '{"stringField":"foo"}' << 'EOF'
{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string","default":"test"}},"required":["stringField"],"title":"SampleRecord","type":"object"}
EOF
# null is not a string, the default does not apply to an explicit null
expect_rejected play-json-single-default '{"stringField":null}' '{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string","default":"test"}},"required":["stringField"],"title":"SampleRecord","type":"object"}'
# the field is required: the validator does not fill in the default
expect_rejected play-json-single-default '{}' '{"$id":"http://example.com/myURI.schema.json","$schema":"http://json-schema.org/draft-07/schema#","description":"Sample schema to help you get started.","properties":{"stringField":{"type":"string","default":"test"}},"required":["stringField"],"title":"SampleRecord","type":"object"}'

log "Create the Streams"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM play_json_single_input_stream WITH (
    KAFKA_TOPIC = 'play-json-single',
    VALUE_FORMAT = 'JSON_SR'
  );

EOF
