#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-10.0.1-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/10.0.x/10.0.1-0/vertica-client-10.0.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# Verify VERTICA has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for VERTICA to start"
docker container logs vertica > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Vertica is now running" ]]; do
sleep 10
docker container logs vertica > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in vertica container do not show 'Vertica is now running' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "VERTICA has started!"

log "Create the table and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytable(f1 varchar(20));
EOF

sleep 2

log "Sending messages to topic mytable"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating JDBC Vertica sink connector"
playground connector create-or-update --connector jdbc-vertica-sink << EOF
{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "topics": "mytable"
          }
EOF

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin > /tmp/result.log  2>&1 <<-EOF
select * from mytable;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
