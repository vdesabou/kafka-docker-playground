#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "mvn"

# based on https://github.com/couchbaselabs/kafka-example-filter
if [ ! -f ${DIR}/../../connect/connect-couchbase-source/event_filter_class_example/target/key-filter-1.0-SNAPSHOT-jar-with-dependencies.jar ]
then
     echo -e "\033[0;33mBuilding KeyFilter\033[0m"
     mvn package -f ${DIR}/../../connect/connect-couchbase-source/event_filter_class_example/pom.xml
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-with-key-filter.yml"

echo -e "\033[0;33mCreating Couchbase cluster\033[0m"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
echo -e "\033[0;33mInstall Couchbase bucket example travel-sample\033[0m"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 /opt/couchbase/samples/travel-sample.zip"
set -e

echo -e "\033[0;33mCreating Couchbase sink connector using event.filter.class=example.KeyFilter\033[0m"
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
     http://localhost:8083/connectors/couchbase-source/config | jq .

sleep 10

echo -e "\033[0;33mVerifying topic test-travel-sample\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-travel-sample --from-beginning --max-messages 2
