#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh

log "Register the Avro schema for Customer"
# {
#     "type": "record",
#     "namespace": "io.confluent.examples.avro",
#     "name": "Customer",
#     "fields": [
#         { "name": "customer_id", "type": "int" },
#         { "name": "customer_name", "type": "string" },
#         { "name": "customer_email", "type": "string" },
#         { "name": "customer_address", "type": "string" }
#     ]
# }
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -X POST http://schema-registry:8081/subjects/customer-value/versions \
  --data '{"schema":"{\"type\":\"record\",\"namespace\":\"io.confluent.examples.avro\",\"name\":\"Customer\",\"fields\":[{\"name\":\"customer_id\",\"type\":\"int\"},{\"name\":\"customer_name\",\"type\":\"string\"},{\"name\":\"customer_email\",\"type\":\"string\"},{\"name\":\"customer_address\",\"type\":\"string\"}]}"}'

log "Register the Avro schema for Product"
# {
#     "type": "record",
#     "namespace": "io.confluent.examples.avro",
#     "name": "Product",
#         "fields": [
#       {"name": "product_id", "type": "int"},
#       {"name": "product_name", "type": "string"},
#       {"name": "product_price", "type": "double"}
#     ]
# }
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -X POST http://schema-registry:8081/subjects/product-value/versions \
  --data '{"schema":"{\"type\":\"record\",\"namespace\":\"io.confluent.examples.avro\",\"name\":\"Product\",\"fields\":[{\"name\":\"product_id\",\"type\":\"int\"},{\"name\":\"product_name\",\"type\":\"string\"},{\"name\":\"product_price\",\"type\":\"double\"}]}"}'

log "Register the Avro schema for AllTypes"
# {
#   "schema":"[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]",
#   "schemaType":"AVRO",
#   "references":[
#     {
#       "name":"io.confluent.examples.avro.Customer",
#       "subject":"customer-value",
#       "version":1
#     },
#     {
#       "name":"io.confluent.examples.avro.Product",
#       "subject":"product-value",
#       "version":1
#     }
#   ]
# }
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -X POST http://schema-registry:8081/subjects/alltypes-value/versions \
  --data '{"schema":"[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]","schemaType":"AVRO","references":[{"name":"io.confluent.examples.avro.Customer","subject":"customer-value","version":1},{"name":"io.confluent.examples.avro.Product","subject":"product-value","version":1}]}'

log "Produce records to alltypes topic"
# Configure the Avro serializer to use your Avro union for serialization, and not the event type, by configuring the following properties in your producer application:
# auto.register.schemas=false
# use.latest.version=true
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic alltypes --property value.schema.id=3 --property auto.register=false --property use.latest.version=true << EOF
{ "io.confluent.examples.avro.Product": { "product_id": 1, "product_name" : "rice", "product_price" : 100.00 } }
{ "io.confluent.examples.avro.Customer": { "customer_id": 100, "customer_name": "acme", "customer_email": "acme@google.com", "customer_address": "1 Main St" } }
EOF

log "Consuming records from this topic"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 \
    --topic alltypes  --from-beginning \
    --property schema.registry.url=http://schema-registry:8081 --property print.schema.ids=true  --property schema.id.separator=: \
    --max-messages 2
