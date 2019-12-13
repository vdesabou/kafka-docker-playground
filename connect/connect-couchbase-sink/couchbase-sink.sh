#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
echo "Creating Couchbase bucket travel-data"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli bucket-create --cluster localhost:8091 --username Administrator --password password --bucket travel-data --bucket-type couchbase --bucket-ramsize 100"

echo "Sending messages to topic couchbase-sink-example"
docker exec json-producer bash -c "java -jar json-producer-example-1.0-SNAPSHOT-jar-with-dependencies.jar"

echo "Creating Couchbase sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSinkConnector",
                    "tasks.max": "2",
                    "topics": "couchbase-sink-example",
                    "connection.cluster_address": "couchbase",
                    "connection.timeout.ms": "2000",
                    "connection.bucket": "travel-data",
                    "connection.username": "Administrator",
                    "connection.password": "password",
                    "couchbase.durability.persist_to": "NONE",
                    "couchbase.durability.replicate_to": "NONE",
                    "couchbase.document.id": "/airport",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/couchbase-sink/config | jq .

sleep 10

echo "Verify data is in Couchbase"
docker exec couchbase bash -c "cbc cat CDG -U couchbase://localhost/travel-data -u Administrator -P password"
docker exec couchbase bash -c "cbc cat LHR -U couchbase://localhost/travel-data -u Administrator -P password"
