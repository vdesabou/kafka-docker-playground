#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.with-transforms.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 -d /opt/couchbase/samples/travel-sample.zip"
set -e

log "Creating Couchbase Source connector with transforms"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
               "tasks.max": "2",
               "couchbase.topic": "default-topic",
               "couchbase.seed.nodes": "couchbase",
               "couchbase.bootstrap.timeout": "2000ms",
               "couchbase.bucket": "travel-sample",
               "couchbase.username": "Administrator",
               "couchbase.password": "password",
               "couchbase.source.handler": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
               "couchbase.event.filter": "com.couchbase.connect.kafka.filter.AllPassFilter",
               "couchbase.stream.from": "SAVED_OFFSET_OR_BEGINNING",
               "couchbase.compression": "ENABLED",
               "couchbase.flow.control.buffer": "128m",
               "couchbase.persistence.polling.interval": "100ms",
               "transforms": "KeyExample,dropSufffix",
               "transforms.KeyExample.type": "io.confluent.connect.transforms.ExtractTopic$Key",
               "transforms.KeyExample.skip.missing.or.null": "true",
               "transforms.dropSufffix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.dropSufffix.regex": "(.*)_.*",
               "transforms.dropSufffix.replacement": "$1",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/couchbase-source/config | jq .

sleep 10

log "Verifying topic airline"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic airline --from-beginning --max-messages 1
log "Verifying topic airport"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic airport --from-beginning --max-messages 1
log "Verifying topic hotel"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic hotel --from-beginning --max-messages 1
log "Verifying topic landmark"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic landmark --from-beginning --max-messages 1
log "Verifying topic route"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic route --from-beginning --max-messages 1
