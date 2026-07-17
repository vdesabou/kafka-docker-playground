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

cd ../../connect/connect-jdbc-ibmdb2-source
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

cd ../../connect/connect-jdbc-ibmdb2-source
# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp ../../connect/connect-jdbc-ibmdb2-source/db2jcc4.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/db2jcc4.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --no-stop

# sample DB is used https://www.ibm.com/docs/en/db2/11.5?topic=samples-sample-database
log "List tables"
playground container exec --container ibmdb2 --command "bash" << EOF
su - db2inst1
db2 connect to sample user db2inst1 using passw0rd
db2 LIST TABLES
EOF

log "Creating JDBC IBM DB2 source connector"
playground connector create-or-update --connector ibmdb2-source  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max": "1",
  "connection.url":"jdbc:db2://ibmdb2:50000/sample",
  "connection.user":"db2inst1",
  "connection.password":"passw0rd",
  "mode": "bulk",
  "table.whitelist": "PURCHASEORDER",
  "topic.prefix": "db2-",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
EOF


sleep 15

log "Verifying topic db2-PURCHASEORDER"
playground topic consume --topic db2-PURCHASEORDER --min-expected-messages 2 --timeout 60


