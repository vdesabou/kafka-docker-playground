#!/bin/bash

set -e

# https://kafka-tutorials.confluent.io/create-tumbling-windows/kstreams.html

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d --build

../../../scripts/wait-for-connect-and-controlcenter.sh

log "Run the connector"
docker cp sqlitekt:/db/geos.db /tmp/geos.db && docker cp /tmp/geos.db connect:/tmp/geos.db
curl -X POST -H Accept:application/json -H Content-Type:application/json http://localhost:8083/connectors/ -d @jdbc_source.config


log "Consume events from the input topic and output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic cities --bootstrap-server broker:9092 --from-beginning --property schema.registry.url=http://localhost:8081 --property print.key=true --property key.deserializer=org.apache.kafka.common.serialization.LongDeserializer --timeout-ms 20000 --max-messages 6

docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic cities_keyed --bootstrap-server broker:9092 --from-beginning --property schema.registry.url=http://localhost:8081 --property print.key=true --property key.deserializer=org.apache.kafka.common.serialization.LongDeserializer --timeout-ms 20000 --max-messages 6