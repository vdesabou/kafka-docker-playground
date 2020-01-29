#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating SNMP Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.snmp.SnmpSourceConnector",
                    "kafka.topic": "snmp-kafka-topic",
                    "snmp.v3.enabled": "true",
                    "snmp.batch.size": "50",
                    "snmp.listen.address": "0.0.0.0",
                    "snmp.listen.port": "10161",
                    "auth.password":"myauthpassword",
                    "privacy.password":"myprivacypassword",
                    "security.name":"mysecurityname",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/snmp-source/config | jq_docker_cli .


sleep 10

log "Test with SNMP v3 trap"
docker exec snmptrap snmptrap -v 3 -c public -u mysecurityname -a MD5 -A myauthpassword -x DES -X myprivacypassword connect:10161 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456

sleep 5

log "Verify we have received the data in snmp-kafka-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic snmp-kafka-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 1