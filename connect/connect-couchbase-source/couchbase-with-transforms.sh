#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-with-transforms.yml"

echo "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
echo "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 /opt/couchbase/samples/travel-sample.zip"
set -e

echo "Creating Couchbase sink connector with transforms"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "couchbase-source",
               "config": {
                    "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
                    "tasks.max": "2",
                    "topic.name": "default-topic",
                    "connection.cluster_address": "couchbase",
                    "connection.timeout.ms": "2000",
                    "connection.bucket": "travel-sample",
                    "connection.username": "Administrator",
                    "connection.password": "password",
                    "use_snapshots": "false",
                    "dcp.message.converter.class": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
                    "event.filter.class": "com.couchbase.connect.kafka.filter.AllPassFilter",
                    "couchbase.stream_from": "SAVED_OFFSET_OR_BEGINNING",
                    "couchbase.compression": "ENABLED",
                    "couchbase.flow_control_buffer": "128m",
                    "couchbase.persistence_polling_interval": "100ms",
                    "transforms": "KeyExample,dropSufffix",
                    "transforms.KeyExample.type": "io.confluent.connect.transforms.ExtractTopic$Key",
                    "transforms.KeyExample.skip.missing.or.null": "true",
                    "transforms.dropSufffix.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.dropSufffix.regex": "(.*)_.*",
                    "transforms.dropSufffix.replacement": "$1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 10

echo "Verifying topic airline"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic airline --from-beginning --max-messages 1
echo "Verifying topic airport"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic airport --from-beginning --max-messages 1
echo "Verifying topic hotel"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic hotel --from-beginning --max-messages 1
echo "Verifying topic landmark"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic landmark --from-beginning --max-messages 1
echo "Verifying topic route"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic route --from-beginning --max-messages 1
