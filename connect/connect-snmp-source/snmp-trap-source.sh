#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating SNMP Source connector"
playground connector create-or-update --connector snmp-source << EOF
{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.snmp.SnmpTrapSourceConnector",
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
          }
EOF


sleep 10

log "Test with SNMP v3 trap"
docker exec snmptrap snmptrap -v 3 -c public -u mysecurityname -l authPriv -a MD5 -A myauthpassword -x DES -X myprivacypassword connect:10161 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456

sleep 5

log "Verify we have received the data in snmp-kafka-topic topic"
playground topic consume --topic snmp-kafka-topic --min-expected-messages 1 --timeout 60
