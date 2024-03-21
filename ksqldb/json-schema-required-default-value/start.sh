#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Create a topic named play-json-single"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-json-single --partitions 1

log "Create a topic named play-json-single-required"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-json-single-required --partitions 1

log "Create a topic named play-json-single-default"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-json-single-default --partitions 1

log "Register the JSON Schema with a single string field"
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
 -X POST http://schema-registry:8081/subjects/play-json-single-value/versions --data '{"schemaType":"JSON","schema":"{\"$id\":\"http:\/\/example.com\/myURI.schema.json\",\"$schema\":\"http:\/\/json-schema.org\/draft-07\/schema#\",\"description\":\"Sample schema to help you get started.\",\"properties\":{\"stringField\":{\"type\":\"string\"}},\"title\":\"SampleRecord\",\"type\":\"object\"}"}'
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
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
 -X POST http://schema-registry:8081/subjects/play-json-single-required-value/versions --data '{"schemaType":"JSON","schema":"{\"$id\":\"http:\/\/example.com\/myURI.schema.json\",\"$schema\":\"http:\/\/json-schema.org\/draft-07\/schema#\",\"description\":\"Sample schema to help you get started.\",\"properties\":{\"stringField\":{\"type\":\"string\"}},\"required\":[\"stringField\"],\"title\":\"SampleRecord\",\"type\":\"object\"}"}'
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
 docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -X POST http://schema-registry:8081/subjects/play-json-single-default-value/versions --data '{"schemaType":"JSON","schema":"{\"$id\":\"http:\/\/example.com\/myURI.schema.json\",\"$schema\":\"http:\/\/json-schema.org\/draft-07\/schema#\",\"description\":\"Sample schema to help you get started.\",\"properties\":{\"stringField\":{\"type\":\"string\",\"default\":\"test\"}},\"required\":[\"stringField\"],\"title\":\"SampleRecord\",\"type\":\"object\"}"}'
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

log "Produce records to the topics"
docker exec -i connect kafka-json-schema-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic play-json-single --property value.schema.id=1 << EOF
{"stringField":"foo"}
EOF

docker exec -i connect kafka-json-schema-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic play-json-single-required --property value.schema.id=2 << EOF
{"stringField":"foo"}
{"stringField":null}
EOF

docker exec -i connect kafka-json-schema-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic play-json-single-default --property value.schema.id=3 << EOF
{"stringField":"foo"}
{"stringField":null}
{}
EOF

log "Create the Streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM play_json_single_input_stream WITH (
    KAFKA_TOPIC = 'play-json-single',
    VALUE_FORMAT = 'JSON_SR'
  );

EOF
