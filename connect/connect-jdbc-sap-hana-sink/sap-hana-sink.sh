#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-sap-hana-sink
if [ ! -f ${PWD}/ngdbc-2.12.9.jar ]
then
     log "Downloading ngdbc-2.12.9.jar "
     wget https://repo1.maven.org/maven2/com/sap/cloud/db/jdbc/ngdbc/2.12.9/ngdbc-2.12.9.jar
fi
cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# Verify SAP HANA has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for SAP HANA to start"
docker container logs sap > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Startup finished!" ]]; do
sleep 10
docker container logs sap > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in sap container do not show 'Startup finished!' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "SAP HANA has started!"

log "Creating SAP HANA JDBC Sink connector"
playground connector create-or-update --connector jdbc-sap-hana-sink << EOF
{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "topics": "testtopic",
               "connection.url": "jdbc:sap://sap:39041/?databaseName=HXE&reconnect=true&statementCacheSize=512",
               "connection.user": "LOCALDEV",
               "connection.password" : "Localdev1",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "auto.create": "true"
          }
EOF

sleep 5

log "Sending records to testtopic topic"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic testtopic --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
{"ID": 222}|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF

sleep 120

log "Check data is in SAP HANA"
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1 << EOF
select * from "LOCALDEV"."testtopic";
EOF
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1  > /tmp/result.log  2>&1 <<-EOF
select * from "LOCALDEV"."testtopic";
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log