#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$CI" ]
then
     # not running with github actions
     if test -z "$(docker images -q oracle/database:12.2.0.1-ee)"
     then
          if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
          then
               logerror "ERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement"
               exit 1
          fi
          log "Building oracle/database:12.2.0.1-ee docker image..it can take a while...(more than 15 minutes!)"
          OLDDIR=$PWD
          rm -rf ${DIR}/docker-images
          git clone https://github.com/oracle/docker-images.git

          cp ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
          cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
          ./buildDockerImage.sh -v 12.2.0.1 -e
          rm -rf ${DIR}/docker-images
          cd ${OLDDIR}
     fi
fi

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"
if [ ! -z "$CI" ]
then
     # if this is github actions, use private image.
     export ORACLE_IMAGE="vdesabou/oracle12"
fi

if [ ! -z "$CONNECTOR_TAG" ]
then
     JDBC_CONNECTOR_VERSION=$CONNECTOR_TAG
else
     JDBC_CONNECTOR_VERSION=$(docker run vdesabou/kafka-docker-playground-connect:${TAG} cat /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/manifest.json | jq -r '.version')
fi
log "JDBC Connector version is $JDBC_CONNECTOR_VERSION"
if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     if [ ! -f ${DIR}/ojdbc8.jar ]
     then
          logerror "ERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext-ssl.yml" down -v --remove-orphans
     log "Starting up oracle container to get generated cert oracle-certificate.crt"
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext-ssl.yml" up -d oracle
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext-no-ojdbc-ssl.yml" down -v --remove-orphans
     log "Starting up oracle container to get generated cert oracle-certificate.crt"
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext-no-ojdbc-ssl.yml" up -d oracle
fi

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

log "Setting up SSL on oracle server..."

log "Creating a wallet in /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet"
docker exec oracle bash -c "orapki wallet create -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet -pwd WalletPasswd123 -auto_login_local"
docker exec oracle bash -c "orapki wallet add -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet  -pwd WalletPasswd123 -dn \"CN=oracle\" -keysize 1024 -self_signed -validity 3650"
docker exec oracle bash -c "orapki wallet display -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet -pwd WalletPasswd123"
docker exec oracle bash -c "orapki wallet export -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet -pwd WalletPasswd123 -dn \"CN=oracle\" -cert /tmp/oracle-certificate.crt"

log "Getting oracle-certificate.crt from oracle server"
docker cp oracle:/tmp/oracle-certificate.crt ${PWD}/ssl/oracle-certificate.crt
cd ${DIR}/ssl
log "Generating OracleTrustStore.jks from oracle-certificate.crt"
rm -f OracleTrustStore.jks
docker run -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${TAG} keytool -noprompt -srcstorepass WalletPasswd123 -deststorepass WalletPasswd123 -import -trustcacerts -alias oracle -file /tmp/oracle-certificate.crt -keystore /tmp/OracleTrustStore.jks
cd ${DIR}

log "Update listener.ora, sqlnet.ora and tnsnames.ora"
docker cp ${PWD}/ssl/listener.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/listener.ora
docker cp ${PWD}/ssl/sqlnet.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/sqlnet.ora
docker cp ${PWD}/ssl/tnsnames.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/tnsnames.ora

docker exec -i oracle lsnrctl << EOF
reload
stop
start
EOF

if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext-ssl.yml" up -d
else
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext-no-ojdbc-ssl.yml" up -d
fi

../../scripts/wait-for-connect-and-controlcenter.sh

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.user": "myuser",
               "connection.password": "mypassword",
               "connection.url": "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLPDB1)))",
               "numeric.mapping":"best_fit",
               "mode":"timestamp",
               "poll.interval.ms":"1000",
               "validate.non.null":"false",
               "table.whitelist":"CUSTOMERS",
               "timestamp.column.name":"UPDATE_TS",
               "topic.prefix":"oracle-",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/oracle-source-ssl/config | jq .

sleep 5

log "Verifying topic oracle-CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-CUSTOMERS --from-beginning --max-messages 2


