#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Wait for Splunk to be up and running"
sleep 60
echo "Splunk UI is accessible at http://127.0.0.1:8000 (admin/password)"

# http://dev.splunk.com/view/event-collector/SP-CAAAE7C#createanhttpeventcollectortokenusingthecli
docker container exec splunk bash -c 'splunk http-event-collector create new-token "kafka" -index log -uri "http://localhost:8889"'

echo "Sending messages to topic splunk-qs"
seq 10 | docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic splunk-qs

echo "Creating Splunk sink connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "SplunkSink",
               "config": {
                    "connector.class": "com.splunk.kafka.connect.SplunkSinkConnector",
                    "tasks.max": "1",
                    "topics": "splunk-qs",
                    "splunk.indexes": "main",
                    "splunk.hec.uri: "http://splunk:8889",
                    "splunk.hec.token": "todo",
                    "splunk.sourcetypes": "my_sourcetype",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 10

echo "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
docker container exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd"
