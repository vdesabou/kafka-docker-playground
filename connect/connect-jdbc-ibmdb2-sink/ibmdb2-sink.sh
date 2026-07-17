#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

log "Starting up ibmdb2 container to get db2jcc4.jar"
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service ibmdb2

cd ../../connect/connect-jdbc-ibmdb2-sink
rm -f db2jcc4.jar
log "Getting db2jcc4.jar"
playground container cp --source ibmdb2:/opt/ibm/db2/V11.5/java/db2jcc4.jar --destination db2jcc4.jar
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
cp db2jcc4.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/db2jcc4.jar
cd -

playground container logs --container ibmdb2 --wait-for-log "Setup has completed" --max-wait 600
log "ibmdb2 DB has started!"

cd ../../connect/connect-jdbc-ibmdb2-sink
# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp ../../connect/connect-jdbc-ibmdb2-sink/db2jcc4.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/db2jcc4.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --no-stop

log "Sending messages to topic ORDERS"
playground topic produce -t ORDERS --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "ID",
      "type": "int"
    },
    {
      "name": "PRODUCT",
      "type": "string"
    },
    {
      "name": "QUANTITY",
      "type": "int"
    },
    {
      "name": "PRICE",
      "type": "float"
    }
  ]
}
EOF

playground topic produce -t ORDERS --nb-messages 1 --forced-value '{"ID":2,"PRODUCT":"foo","QUANTITY":2,"PRICE":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "ID",
      "type": "int"
    },
    {
      "name": "PRODUCT",
      "type": "string"
    },
    {
      "name": "QUANTITY",
      "type": "int"
    },
    {
      "name": "PRICE",
      "type": "float"
    }
  ]
}
EOF

log "Creating JDBC IBM DB2 sink connector"
playground connector create-or-update --connector ibmdb2-sink  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url":"jdbc:db2://ibmdb2:50000/sample",
  "connection.user":"db2inst1",
  "connection.password":"passw0rd",
  "topics": "ORDERS",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true",
  "auto.create": "true"
}
EOF


sleep 15

log "Check data is in IBM DB2"
playground container exec --container ibmdb2 --command "bash" > /tmp/result.log << EOF
su - db2inst1
db2 connect to sample user db2inst1 using passw0rd
db2 select ID,PRODUCT,QUANTITY,PRICE from ORDERS
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

