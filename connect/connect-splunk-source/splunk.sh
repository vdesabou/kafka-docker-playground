#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating Splunk sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "SplunkSink",
               "config": {
                    "connector.class": "io.confluent.connect.SplunkHttpSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "splunk-source",
                    "splunk.collector.index.default": "default-index",
                    "splunk.port": "8889",
                    "splunk.ssl.key.store.path": "/tmp/keystore.jks",
                    "splunk.ssl.key.store.password": "confluent",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Simulate an application sending data to the connector"
curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'

sleep 5

echo "Verifying topic splunk-source"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic splunk-source --from-beginning --max-messages 1

