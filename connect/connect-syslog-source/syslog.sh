#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "nc"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Syslog Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.syslog.SyslogSourceConnector",
                    "syslog.port": "5454",
                    "syslog.listener": "TCP",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/syslog-source/config | jq .


sleep 5

log "Test with sample syslog-formatted message sent via netcat"
echo "<34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - Your refrigerator is running" | nc -v -w 0 localhost 5454

sleep 5

log "Verify we have received the data in syslog topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic syslog --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 1