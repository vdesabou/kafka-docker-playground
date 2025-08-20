#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.3.2"
then
     logwarn "minimal supported connector version is 1.3.3 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating SNMP Source connector"
playground connector create-or-update --connector snmp-source  << EOF
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
     "confluent.topic.replication.factor": "1",

     "_comment": "since 1.3.0",
     "v3.security.context.users": "mysecurityname",
     "v3.mysecurityname.auth.password": "myauthpassword",
     "v3.mysecurityname.auth.protocol": "md5",
     "v3.mysecurityname.privacy.password": "myprivacypassword",
     "v3.mysecurityname.privacy.protocol": "des"
}
EOF


sleep 10

log "Test with SNMP v3 trap"
docker exec snmptrap snmptrap -v 3 -c public -u mysecurityname -l authPriv -a MD5 -A myauthpassword -x DES -X myprivacypassword connect:10161 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456

sleep 5

log "Verify we have received the data in snmp-kafka-topic topic"
playground topic consume --topic snmp-kafka-topic --min-expected-messages 1 --timeout 60
