#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_solace () {
     MAX_WAIT=240
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for Solace to startup"
     docker container logs solace > /tmp/out.txt 2>&1
     while ! grep "Running pre-startup checks" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs solace > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Running pre-startup checks' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "Solace is started!"
     sleep 30
}

if [ ! -f ${DIR}/sol-jms-10.6.4.jar ]
then
     log "Downloading sol-jms-10.6.4.jar"
     wget https://repo1.maven.org/maven2/com/solacesystems/sol-jms/10.6.4/sol-jms-10.6.4.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

wait_for_solace
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

log "Create the queue connector-quickstart in the default Message VPN using CLI"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"

log "Publish messages to the Solace queue using the REST endpoint"

for i in 1000 1001 1002
do
     curl -X POST -d "m1" http://localhost:9000/Queue/connector-quickstart -H "Content-Type: text/plain" -H "Solace-Message-ID: $i"
done

log "Creating Solace source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/solace-source/config | jq .

log "Verifying topic from-solace-messages"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic from-solace-messages --from-beginning --max-messages 2
