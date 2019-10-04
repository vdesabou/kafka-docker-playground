#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Wait for Solace to be up and running"
sleep 60

echo "Create the queue connector-quickstart in the default Message VPN using CLI"
docker container exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"

echo "Publish messages to the Solace queue using the REST endpoint"

for i in 1000 1001 1002
do
     curl -X POST -d "m1" http://localhost:9000/Queue/connector-quickstart -H "Content-Type: text/plain" -H "Solace-Message-ID: $i"
done

echo "Creating Solace source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "SolaceSourceConnector1",
               "config": {
                    "connector.class": "io.confluent.connect.solace.SolaceSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "from-solace-messages",
                    "solace.host": "smf://solace:55555",
                    "solace.username": "admin",
                    "solace.password": "admin",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

echo "Verifying topic from-solace-messages"
docker container exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic from-solace-messages --from-beginning --max-messages 2
