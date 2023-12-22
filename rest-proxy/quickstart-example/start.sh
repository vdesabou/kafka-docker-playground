#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure rest-proxy is not disabled
export ENABLE_RESTPROXY=true=true

playground start-environment --environment plaintext

# JSON Messages
log "Produce and Consume JSON Messages"
# Produce a message using JSON with the value '{ "foo": "bar" }' to the topic jsontest
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.json.v2+json" \
      --data '{"records":[{"value":{"foo":"bar"}}]}' "http://rest-proxy:8082/topics/jsontest"
# Expected output from preceding command
# {"offsets":[{"partition":0,"offset":0,"error_code":null,"error":null}],"key_schema_id":null,"value_schema_id":null}

# Create a consumer for JSON data in "my_json_consumer_group" consumer group, starting at the beginning of the topic's
# log and subscribe to a topic. Then consume some data using the base URL in the first response.
# Finally, close the consumer with a DELETE to make it leave the group and clean up its resources.
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" \
      --data '{"name": "my_consumer_instance", "format": "json", "auto.offset.reset": "earliest"}' \
      http://rest-proxy:8082/consumers/my_json_consumer_group
# expected Output
# {"instance_id":"my_consumer_instance","base_uri":"http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance"}%

# Subscribe to the given list of topics or a topic pattern to get dynamically assigned partitions.
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" --data '{"topics":["jsontest"]}' \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/subscription

# consuming records from the topic jsontest
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.json.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.json.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/records
# Expected output
# [{"topic":"jsontest","key":null,"value":{"foo":"bar"},"partition":0,"offset":0}]

# Destroy the consumer instance.
docker exec -i rest-proxy curl -X DELETE -H "Content-Type: application/vnd.kafka.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance


log "Produce and Consume Avro Messages"
# Produce a message using Avro embedded data, including the schema which will
# be registered with schema registry and used to validate and serialize
# before storing the data in Kafka
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.avro.v2+json" \
      -H "Accept: application/vnd.kafka.v2+json" \
      --data '{"value_schema": "{\"type\": \"record\", \"name\": \"User\", \"fields\": [{\"name\": \"name\", \"type\": \"string\"}]}", "records": [{"value": {"name": "testUser"}}]}' \
      "http://rest-proxy:8082/topics/avrotest"

# Produce a message with Avro key and value.
# Note that if you use Avro values you must also use Avro keys, but the schemas can differ
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.avro.v2+json" \
      -H "Accept: application/vnd.kafka.v2+json" \
      --data '{"key_schema": "{\"name\":\"user_id\"  ,\"type\": \"int\"   }", "value_schema": "{\"type\": \"record\", \"name\": \"User\", \"fields\": [{\"name\": \"name\", \"type\": \"string\"}]}", "records": [{"key" : 1 , "value": {"name": "testUser"}}]}' \
      "http://rest-proxy:8082/topics/avrokeytest2"

# Create a consumer for Avro data in "my_avro_consumer_group" consumer group, starting at the beginning of the topic's
# log and subscribe to a topic. Then consume some data from a topic, which is decoded, translated to
# JSON, and included in the response. The schema used for deserialization is
# fetched automatically from schema registry. Finally, clean up.
docker exec -i rest-proxy curl -X POST  -H "Content-Type: application/vnd.kafka.v2+json" \
      --data '{"name": "my_consumer_instance", "format": "avro", "auto.offset.reset": "earliest"}' \
      http://rest-proxy:8082/consumers/my_avro_consumer_group

docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" --data '{"topics":["avrotest"]}' \
      http://rest-proxy:8082/consumers/my_avro_consumer_group/instances/my_consumer_instance/subscription

#consume records
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.avro.v2+json" \
      http://rest-proxy:8082/consumers/my_avro_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.avro.v2+json" \
      http://rest-proxy:8082/consumers/my_avro_consumer_group/instances/my_consumer_instance/records
#expected output: [{"topic":"avrotest","key":null,"value":{"name":"testUser"},"partition":0,"offset":0}]

docker exec -i rest-proxy curl -X DELETE -H "Content-Type: application/vnd.kafka.v2+json" \
      http://rest-proxy:8082/consumers/my_avro_consumer_group/instances/my_consumer_instance


log "Produce and Consume Binary Messages"
# Produce a message using binary embedded data with value "Kafka" to the topic binarytest
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.binary.v2+json" \
      -H "Accept: application/vnd.kafka.v2+json" \
      --data '{"records":[{"value":"S2Fma2E="}]}' "http://rest-proxy:8082/topics/binarytest"

# Expected output from preceding command:
# {"offsets":[{"partition":0,"offset":0,"error_code":null,"error":null}],"key_schema_id":null,"value_schema_id":null}

# Create a consumer for binary data in "my_binary_consumer_group" consumer group, starting at the beginning of the topic's
# log. Then consume some data from a topic using the base URL in the first response.
# Finally, close the consumer with a DELETE to make it leave the group and clean up
# its resources.
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" \
      --data '{"name": "my_consumer_instance", "format": "binary", "auto.offset.reset": "earliest"}' \
      http://rest-proxy:8082/consumers/my_binary_consumer_group
# Expected output from preceding command:
# {"instance_id":"my_consumer_instance","base_uri":"http://rest-proxy:8082/consumers/my_binary_consumer_group/instances/my_consumer_instance"}

docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" --data '{"topics":["binarytest"]}' \
      http://rest-proxy:8082/consumers/my_binary_consumer_group/instances/my_consumer_instance/subscription

docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.binary.v2+json" \
      http://rest-proxy:8082/consumers/my_binary_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.binary.v2+json" \
      http://rest-proxy:8082/consumers/my_binary_consumer_group/instances/my_consumer_instance/records
# Expected output from preceding command: [{"key":null,"value":"S2Fma2E=","partition":0,"offset":0,"topic":"binarytest"}]

docker exec -i rest-proxy curl -X DELETE -H "Content-Type: application/vnd.kafka.v2+json" \
      http://rest-proxy:8082/consumers/my_binary_consumer_group/instances/my_consumer_instance


log "Produce and Consume Protobuf Messages"
# Produce a message using Protobuf embedded data, including the schema which will
# be registered with schema registry and used to validate and serialize
# before storing the data in Kafka
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.protobuf.v2+json" \
   -H "Accept: application/vnd.kafka.v2+json" \
   --data '{"value_schema": "syntax=\"proto3\"; message User { string name = 1; }", "records": [{"value": {"name": "testUser"}}]}' \
   "http://rest-proxy:8082/topics/protobuftest"

# Expected output from preceding command:
# {"offsets":[{"partition":0,"offset":0,"error_code":null,"error":null}],"key_schema_id":null,"value_schema_id":21}

# Create a consumer for Protobuf data in "my_protobuf_consumer_group" consumer group, starting at the beginning of the topic's
# log and subscribe to a topic. Then consume some data from a topic, which is decoded, translated to
# JSON, and included in the response. The schema used for deserialization is
# fetched automatically from schema registry. Finally, clean up.
docker exec -i rest-proxy curl -X POST  -H "Content-Type: application/vnd.kafka.protobuf.v2+json" \
      --data '{"name": "my_consumer_instance", "format": "protobuf", "auto.offset.reset": "earliest"}' \
      http://rest-proxy:8082/consumers/my_protobuf_consumer_group

# Expected output from preceding command:
# {"instance_id":"my_consumer_instance","base_uri":"http://rest-proxy:8082/consumers/my_protobuf_consumer_group/instances/my_consumer_instance"}

docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.protobuf.v2+json" --data '{"topics":["protobuftest"]}' \
      http://rest-proxy:8082/consumers/my_protobuf_consumer_group/instances/my_consumer_instance/subscription

docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.protobuf.v2+json" \
      http://rest-proxy:8082/consumers/my_protobuf_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.protobuf.v2+json" \
      http://rest-proxy:8082/consumers/my_protobuf_consumer_group/instances/my_consumer_instance/records
# Expected output from preceding command:
# [{"key":null,"value":{"name":"testUser"},"partition":0,"offset":1,"topic":"protobuftest"}]

docker exec -i rest-proxy curl -X DELETE -H "Content-Type: application/vnd.kafka.protobuf.v2+json" \
      http://rest-proxy:8082/consumers/my_protobuf_consumer_group/instances/my_consumer_instance


log "Produce and Consume JSON Schema Messages"
# Produce a message using JSON schema embedded data, including the schema which will
# be registered with schema registry and used to validate and serialize
# before storing the data in Kafka
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.jsonschema.v2+json" \
   -H "Accept: application/vnd.kafka.v2+json" \
   --data '{"value_schema": "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}", "records": [{"value": {"name": "testUser"}}]}' \
   "http://rest-proxy:8082/topics/jsonschematest"

# Expected output from preceding command:
# {"offsets":[{"partition":0,"offset":0,"error_code":null,"error":null}],"key_schema_id":null,"value_schema_id":21}

# Create a consumer for JSON schema data in "my_jsonschema_consumer_group" consumer group, starting at the beginning of the topic's
# log and subscribe to a topic. Then consume some data from a topic, which is decoded, translated to
# JSON, and included in the response. The schema used for deserialization is
# fetched automatically from schema registry. Finally, clean up.
docker exec -i rest-proxy curl -X POST  -H "Content-Type: application/vnd.kafka.jsonschema.v2+json" \
      --data '{"name": "my_consumer_instance", "format": "jsonschema", "auto.offset.reset": "earliest"}' \
      http://rest-proxy:8082/consumers/my_jsonschema_consumer_group

# Expected output from preceding command:
# {"instance_id":"my_consumer_instance","base_uri":"http://rest-proxy:8082/consumers/my_jsonschema_consumer_group/instances/my_consumer_instance"}

docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.jsonschema.v2+json" --data '{"topics":["jsonschematest"]}' \
      http://rest-proxy:8082/consumers/my_jsonschema_consumer_group/instances/my_consumer_instance/subscription

docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.jsonschema.v2+json" \
      http://rest-proxy:8082/consumers/my_jsonschema_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.jsonschema.v2+json" \
      http://rest-proxy:8082/consumers/my_jsonschema_consumer_group/instances/my_consumer_instance/records
# Expected output from preceding command:
# [{"key":null,"value":{"name":"testUser"},"partition":0,"offset":1,"topic":"jsonschematest"}]

docker exec -i rest-proxy curl -X DELETE -H "Content-Type: application/vnd.kafka.jsonschema.v2+json" \
      http://rest-proxy:8082/consumers/my_jsonschema_consumer_group/instances/my_consumer_instance


log "Inspect Topic Metadata"
# Get a list of topics
docker exec -i rest-proxy curl "http://rest-proxy:8082/topics"
# Expected output from preceding command:
#["__consumer_offsets","_schemas","avrotest","binarytest","jsontest"]

# Get info about one topic
docker exec -i rest-proxy curl "http://rest-proxy:8082/topics/avrotest"

# Expected output from preceding command:
# {"name":"avrotest","configs":{"message.downconversion.enable":"true","file.delete.delay.ms":"60000",\
# "segment.ms":"604800000","min.compaction.lag.ms":"0","retention.bytes":"-1","segment.index.bytes":"10485760",\
# "cleanup.policy":"delete","follower.replication.throttled.replicas":"",\
# "message.timestamp.difference.max.ms":"9223372036854775807","segment.jitter.ms":"0","preallocate":"false",\
# "message.timestamp.type":"CreateTime","message.format.version":"2.0-IV1","segment.bytes":"1073741824",\
# "unclean.leader.election.enable":"false","max.message.bytes":"1000012","retention.ms":"604800000",\
# "flush.ms":"9223372036854775807","delete.retention.ms":"86400000","leader.replication.throttled.replicas":"",\
# "min.insync.replicas":"1","flush.messages":"9223372036854775807","compression.type":"producer",\
# "index.interval.bytes":"4096","min.cleanable.dirty.ratio":"0.5"},"partitions":\
# [{"partition":0,"leader":0,"replicas":[{"broker":0,"leader":true,"in_sync":true}]}]}
# ...

# Get info about a topic's partitions
docker exec -i rest-proxy curl "http://rest-proxy:8082/topics/avrotest/partitions"
# Expected output from preceding command:
# [{"partition":0,"leader":0,"replicas":[{"broker":0,"leader":true,"in_sync":true}]}]
