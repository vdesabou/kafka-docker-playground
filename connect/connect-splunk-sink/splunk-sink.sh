#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mSplunk UI is accessible at http://127.0.0.1:8000 (admin/password)\033[0m"

# echo -e "\033[0;33mSetting minfreemb to 1Gb (by default 5Gb)\033[0m"
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk set minfreemb 1000 -auth "admin:password"'
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk restart'
# sleep 60

echo -e "\033[0;33mCreate topic splunk-qs\033[0m"
docker exec broker kafka-topics --create --topic splunk-qs --partitions 10 --replication-factor 1 --zookeeper zookeeper:2181


echo -e "\033[0;33mCreating Splunk sink connector\033[0m"
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


echo -e "\033[0;33mSending messages to topic splunk-qs\033[0m"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic splunk-qs << EOF
This is a test with Splunk 1
This is a test with Splunk 2
This is a test with Splunk 3
EOF

echo -e "\033[0;33mSleeping 60 seconds\033[0m"
sleep 60

echo -e "\033[0;33mVerify data is in splunk\033[0m"
docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk search "source=\"http:splunk_hec_token\"" -auth "admin:password"'
