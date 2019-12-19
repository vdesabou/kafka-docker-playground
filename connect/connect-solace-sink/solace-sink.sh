#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/sol-jms-10.6.0.jar ]
then
     echo -e "\033[0;33mDownloading sol-jms-10.6.0.jar\033[0m"
     wget http://central.maven.org/maven2/com/solacesystems/sol-jms/10.6.3/sol-jms-10.6.0.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mWait 60 seconds for Solace to be up and running\033[0m"
sleep 60
echo -e "\033[0;33mSolace UI is accessible at http://127.0.0.1:8080 (admin/admin)\033[0m"

echo -e "\033[0;33mSending messages to topic sink-messages\033[0m"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

echo -e "\033[0;33mCreating Solace sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.SolaceSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "solace.host": "smf://solace:55555",
                    "solace.username": "admin",
                    "solace.password": "admin",
                    "solace.dynamic.durables": "true",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/SolaceSinkConnector/config | jq .

sleep 10

echo -e "\033[0;33mConfirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI\033[0m"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd"
