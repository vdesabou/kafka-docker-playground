#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


# based on https://github.com/couchbaselabs/kafka-example-filter
if [ ! -f ${DIR}/../../connect/connect-couchbase-source/event_filter_class_example/target/key-filter-1.0.0-SNAPSHOT-jar-with-dependencies.jar ]
then
     log "Building KeyFilter"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/event_filter_class_example":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/event_filter_class_example/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-with-key-filter.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 /opt/couchbase/samples/travel-sample.zip"
set -e

log "Creating Couchbase Source connector using couchbase.event.filter=example.KeyFilter"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
                    "tasks.max": "2",
                    "couchbase.topic": "test-travel-sample",
                    "couchbase.seed.nodes": "couchbase",
                    "couchbase.bootstrap.timeout": "2000ms",
                    "couchbase.bucket": "travel-sample",
                    "couchbase.username": "Administrator",
                    "couchbase.password": "password",
                    "couchbase.source.handler": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
                    "couchbase.event.filter": "example.KeyFilter",
                    "couchbase.stream.from": "SAVED_OFFSET_OR_BEGINNING",
                    "couchbase.compression": "ENABLED",
                    "couchbase.flow.control.buffer": "128m",
                    "couchbase.persistence.polling.interval": "100ms"
          }' \
     http://localhost:8083/connectors/couchbase-source/config | jq .

sleep 10

log "Verifying topic test-travel-sample"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-travel-sample --from-beginning --max-messages 2
