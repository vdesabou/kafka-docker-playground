#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-9.3.1-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/9.3.x/9.3.1-0/vertica-client-9.3.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-9.3.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-9.3.1-0.x86_64.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-tombstone.yml"


sleep 60

log "Sending messages to topic customer using java producer from connect-vertica-sink/producer"

log "Creating JDBC Vertica sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "pk.mode": "record_key",
                    "pk.fields": "ID",
                    "auto.create": true,
                    "auto.evolve": false,
                    "key.converter": "org.apache.kafka.connect.converters.LongConverter",
                    "value.converter" : "Avro",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "topics": "customer"
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from customer;
EOF

#  ListID | NormalizedHashItemID |                                               URL                                               |   MyFloatValue    |  MyTimestamp  | ID
# --------+----------------------+-------------------------------------------------------------------------------------------------+-------------------+---------------+-----
#       0 |                    0 | url                                                                                             | 0.282263566813515 | 1594792587099 |   0
#       1 |                    1 | url                                                                                             | 0.282263566813515 | 1594792588953 |   1
#       1 |                    1 | url                                                                                             | 0.282263566813515 | 1594792588953 |   2
#         |                      |                                                                                                 |                   | 1594792589169 |   3
#       4 |                    4 | ultralongurlultralongurlultralongurlultralongurlultralongurlultralongurlultralongurultralongurl | 0.282263566813515 | 1594792589275 |   4
#       5 |                    5 | url                                                                                             | 0.282263566813515 | 1594792589380 |   5
