#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$DISABLE_CONTROL_CENTER" ]
then
  profile_control_center_command="--profile control-center"
else
  log "🛑 control-center is disabled"
fi

profile_ksqldb_command=""
if [ -z "$DISABLE_KSQLDB" ]
then
  profile_ksqldb_command="--profile ksqldb"
else
  log "🛑 ksqldb is disabled"
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} down -v --remove-orphans
log "Starting up ibmdb2 container to get db2jcc4.jar"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d ibmdb2

rm -f ${DIR}/db2jcc4.jar
log "Getting db2jcc4.jar"
docker cp ibmdb2:/opt/ibm/db2/V11.5/java/db2jcc4.jar ${DIR}/db2jcc4.jar

# Verify IBM DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for IBM DB to start"
docker container logs ibmdb2 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Setup has completed" ]]; do
sleep 10
docker container logs ibmdb2 > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in ibmdb2 container do not show 'Setup has completed' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "ibmdb2 DB has started!"

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d

../../scripts/wait-for-connect-and-controlcenter.sh

# Keep it for utils.sh
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic ORDERS"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"ID","type":"int"},{"name":"PRODUCT", "type": "string"}, {"name":"QUANTITY", "type": "int"}, {"name":"PRICE",
"type": "float"}]}' << EOF
{"ID": 999, "PRODUCT": "foo", "QUANTITY": 100, "PRICE": 50}
EOF

log "Creating JDBC IBM DB2 sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url":"jdbc:db2://ibmdb2:25010/sample",
               "connection.user":"db2inst1",
               "connection.password":"passw0rd",
               "topics": "ORDERS",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/ibmdb2-sink/config | jq .


sleep 15

log "Check data is in IBM DB2"
docker exec -i ibmdb2 bash << EOF > /tmp/result.log
su - db2inst1
db2 connect to sample user db2inst1 using passw0rd
db2 select ID,PRODUCT,QUANTITY,PRICE from ORDERS
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

