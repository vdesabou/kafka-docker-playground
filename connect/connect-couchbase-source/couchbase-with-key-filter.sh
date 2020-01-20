#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "mvn"

# based on https://github.com/couchbaselabs/kafka-example-filter
if [ ! -f ${DIR}/../../connect/connect-couchbase-source/event_filter_class_example/target/key-filter-1.0-SNAPSHOT-jar-with-dependencies.jar ]
then
     log "Building KeyFilter"
     mvn package -f ${DIR}/../../connect/connect-couchbase-source/event_filter_class_example/pom.xml
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-with-key-filter.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 /opt/couchbase/samples/travel-sample.zip"
set -e

log "Creating Couchbase sink connector using event.filter.class=example.KeyFilter"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
                    "tasks.max": "2",
                    "topic.name": "test-travel-sample",
                    "connection.cluster_address": "couchbase",
                    "connection.timeout.ms": "2000",
                    "connection.bucket": "travel-sample",
                    "connection.username": "Administrator",
                    "connection.password": "password",
                    "use_snapshots": "false",
                    "dcp.message.converter.class": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
                    "event.filter.class": "example.KeyFilter",
                    "couchbase.stream_from": "SAVED_OFFSET_OR_BEGINNING",
                    "couchbase.compression": "ENABLED",
                    "couchbase.flow_control_buffer": "128m",
                    "couchbase.persistence_polling_interval": "100ms"
          }' \
     http://localhost:8083/connectors/couchbase-source/config | jq_docker_cli .

sleep 10

log "Verifying topic test-travel-sample"
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-travel-sample --from-beginning --max-messages 2
