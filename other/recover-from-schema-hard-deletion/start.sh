#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Producing a message to ORDERS topic with a schema"
docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 \
    --topic ORDERS \
    --property schema.registry.url=http://schema-registry:8081  \
    --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

log "---"
log "Checking the schema existence in the schema registry"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/ORDERS-value/versions/1

log "---"
log "Consuming the message with the existing schema and printing the schema ID"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 \
    --topic ORDERS  --from-beginning \
    --property schema.registry.url=http://schema-registry:8081 --property print.schema.ids=true  --property schema.id.separator=: \
    --max-messages 1

log "---"
log "Hard deleting the schema from the schema registry"
docker exec -i connect curl -s -X DELETE http://schema-registry:8081/subjects/ORDERS-value/versions/1  --output /dev/null
docker exec -i connect curl -s -X DELETE http://schema-registry:8081/subjects/ORDERS-value/versions/1?permanent=true  --output /dev/null

status_code=$(docker exec -i connect curl --write-out %{http_code} --silent --output /dev/null http://schema-registry:8081/subjects/ORDERS-value/versions/1)
if [[ "$status_code" -ne 404 ]] ; then
    log "Schema not deleted"
    exit 0
fi

log "---"
log "Trying to consume the message with the deleted schema"
(docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 \
    --topic ORDERS  --from-beginning \
    --property schema.registry.url=http://schema-registry:8081 \
    --max-messages 1) || log "Consumption failed as expected"


log "Consuming the message with WireMock mocking the schema registry"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 \
    --topic ORDERS  --from-beginning \
    --property schema.registry.url=http://wiremock:8080 \
    --max-messages 1
