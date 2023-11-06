#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure rest-proxy is not disabled
export ENABLE_RESTPROXY=true

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

sleep 5

log "Create a topic named test-data-contracts"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic test-data-contracts --partitions 1
log "Produce records to the topic test-data-contracts"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --topic test-data-contracts --property schema.registry.url=http://schema-registry:8081 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property value.rule.set='{"domainRules":[{ "name": "checkLen", "kind": "CONDITION", "type": "CEL","mode": "WRITE", "expr": "size(message.f1) < 10","onFailure": "ERROR"}]}' << EOF
{"f1": "success"}
EOF

log "Consume records from this topic"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 --topic test-data-contracts --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 1

set +e
log "Produce a record that will fail"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --topic test-data-contracts --property schema.registry.url=http://schema-registry:8081 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property value.rule.set='{"domainRules":[{ "name": "checkLen", "kind": "CONDITION", "type": "CEL","mode": "WRITE", "expr": "size(message.f1) < 10","onFailure": "ERROR"}]}' << EOF
{"f1": "this will fail"}
EOF
# Expected output:
# org.apache.kafka.common.errors.SerializationException: Error serializing Avro message
# 	at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:174)
# 	at io.confluent.kafka.formatter.AvroMessageReader$AvroMessageSerializer.serialize(AvroMessageReader.java:167)
# 	at io.confluent.kafka.formatter.SchemaMessageReader.readMessage(SchemaMessageReader.java:406)
# 	at kafka.tools.ConsoleProducer$$anon$1$$anon$2.hasNext(ConsoleProducer.scala:67)
# 	at kafka.tools.ConsoleProducer$.loopReader(ConsoleProducer.scala:90)
# 	at kafka.tools.ConsoleProducer$.main(ConsoleProducer.scala:99)
# 	at kafka.tools.ConsoleProducer.main(ConsoleProducer.scala)
# Caused by: org.apache.kafka.common.errors.SerializationException: Rule failed: checkLen
# 	at io.confluent.kafka.schemaregistry.rules.ErrorAction.run(ErrorAction.java:32)
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.runAction(AbstractKafkaSchemaSerDe.java:744)
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.executeRules(AbstractKafkaSchemaSerDe.java:701)
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.executeRules(AbstractKafkaSchemaSerDe.java:625)
# 	at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:144)
# 	... 6 more
# Caused by: io.confluent.kafka.schemaregistry.rules.RuleException: Expr failed: 'size(message.f1) < 10'
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.executeRules(AbstractKafkaSchemaSerDe.java:687)
# 	... 8 more

log "Create a topic named orders"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic orders --partitions 1

log "Register a new schema for the topic Orders"
docker exec -i connect jq -n --rawfile schema /data/order.avsc '{schema: $schema}' | docker exec -i connect curl http://schema-registry:8081/subjects/orders-value/versions -H "Content-Type: application/json" -d @-

log "We start a producer, and pass the schema ID that was returned during registration as the value of value.schema.id."
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --topic orders --property schema.registry.url=http://schema-registry:8081 --property value.schema.id=2 << EOF
{"orderId": 1, "customerId": 2, "totalPriceCents": 12000, "state": "Pending", "timestamp": 1693591356 }
EOF

log "Enhancing the data contract with metadata"
docker exec -i connect curl http://schema-registry:8081/subjects/orders-value/versions  -H "Content-Type: application/json" -d @/data/order_metadata.json

log "Adding data quality rules to the data contract"
docker exec -i connect curl http://schema-registry:8081/subjects/orders-value/versions -H "Content-Type: application/json" -d @/data/order_ruleset.json
# The above rule will cause all messages with a non-positive price to be rejected.
# {
#   "ruleSet": {
#     "domainRules": [
#       {
#         "name": "checkTotalPrice",
#         "kind": "CONDITION",
#         "type": "CEL",
#         "mode": "WRITE",
#         "expr": "message.totalPriceCents > 0"
#       }
#     ]
#   }

log "We can produce a record to this topic"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --topic orders --property schema.registry.url=http://schema-registry:8081 --property value.schema.id=4 << EOF
{"orderId": 1, "customerId": 2, "totalPriceCents": 15, "state": "Pending", "timestamp": 1693591356 }
EOF

log "Let's try with a message with a non-positive price. This record should be rejected."
set +e
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --topic orders --property schema.registry.url=http://schema-registry:8081 --property value.schema.id=4 << EOF
{"orderId": 1, "customerId": 2, "totalPriceCents": -1, "state": "Pending", "timestamp": 1693591356 }
EOF
# Expected output
# org.apache.kafka.common.errors.SerializationException: Error serializing Avro message
# 	at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:174)
# 	at io.confluent.kafka.formatter.AvroMessageReader$AvroMessageSerializer.serialize(AvroMessageReader.java:167)
# 	at io.confluent.kafka.formatter.SchemaMessageReader.readMessage(SchemaMessageReader.java:406)
# 	at kafka.tools.ConsoleProducer$$anon$1$$anon$2.hasNext(ConsoleProducer.scala:67)
# 	at kafka.tools.ConsoleProducer$.loopReader(ConsoleProducer.scala:90)
# 	at kafka.tools.ConsoleProducer$.main(ConsoleProducer.scala:99)
# 	at kafka.tools.ConsoleProducer.main(ConsoleProducer.scala)
# Caused by: org.apache.kafka.common.errors.SerializationException: Rule failed: checkTotalPrice
# 	at io.confluent.kafka.schemaregistry.rules.ErrorAction.run(ErrorAction.java:32)
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.runAction(AbstractKafkaSchemaSerDe.java:744)
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.executeRules(AbstractKafkaSchemaSerDe.java:701)
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.executeRules(AbstractKafkaSchemaSerDe.java:625)
# 	at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:144)
# 	... 6 more
# Caused by: io.confluent.kafka.schemaregistry.rules.RuleException: Expr failed: 'message.totalPriceCents > 0'
# 	at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.executeRules(AbstractKafkaSchemaSerDe.java:687)
# 	... 8 more

log "Try to produce record with REST Proxy"
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.avro.v2+json" \
      -H "Accept: application/vnd.kafka.v2+json" \
      --data '{"value_schema_id": "4", "records": [{"value": {"orderId": 1, "customerId": 2, "totalPriceCents": 15, "state": "Pending", "timestamp": 1693591356}}]}' \
      http://rest-proxy:8082/topics/orders
