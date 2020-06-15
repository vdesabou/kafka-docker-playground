#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Splunk UI is accessible at http://127.0.0.1:8000 (admin/password)"

# log "Setting minfreemb to 1Gb (by default 5Gb)"
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk set minfreemb 1000 -auth "admin:password"'
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk restart'
# sleep 60

log "Create topic splunk-qs"
docker exec broker kafka-topics --create --topic splunk-qs --partitions 10 --replication-factor 1 --zookeeper zookeeper:2181


log "Creating Splunk sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.splunk.kafka.connect.SplunkSinkConnector",
                    "tasks.max": "1",
                    "topics": "splunk-qs",
                    "splunk.indexes": "main",
                    "splunk.hec.uri": "http://splunk:8088",
                    "splunk.hec.token": "99582090-3ac3-4db1-9487-e17b17a05081",
                    "splunk.sourcetypes": "my_sourcetype",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/splunk-sink/config | jq .


log "Sending messages to topic splunk-qs"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic splunk-qs << EOF
This is a test with Splunk 1
This is a test with Splunk 2
This is a test with Splunk 3
EOF

log "Sleeping 60 seconds"
sleep 60

log "Verify data is in splunk"
output=$(docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk search "source=\"http:splunk_hec_token\"" -auth "admin:password"')
if [[ ! $output == "This is a test with Splunk"* ]]; then
  logerror "Fail: something is wrong !"
  exit 1
fi