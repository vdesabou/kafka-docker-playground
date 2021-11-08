#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"

if test -z "$(docker images -q $ORACLE_IMAGE)"
then
    if [ ! -z "$CI" ]
    then
        if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
        then
            # running with github actions
            aws s3 cp --only-show-errors s3://kafka-docker-playground/3rdparty/linuxx64_12201_database.zip .
        fi
    fi
    if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
    then
        logerror "ERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement"
        exit 1
    fi
    log "Building $ORACLE_IMAGE docker image..it can take a while...(more than 15 minutes!)"
    OLDDIR=$PWD
    rm -rf ${DIR}/docker-images
    git clone https://github.com/oracle/docker-images.git

    mv ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
    cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
    ./buildContainerImage.sh -v 12.2.0.1 -e
    rm -rf ${DIR}/docker-images
    cd ${OLDDIR}
fi

OLD_ORACLE_IMAGE=$ORACLE_IMAGE
# https://github.com/oracle/docker-images/tree/main/OracleDatabase/SingleInstance/samples/prebuiltdb
SETUP_FOLDER=$(pwd)/ora-setup-scripts
SETUP_FILE=${SETUP_FOLDER}/01_user-setup.sh
SETUP_FILE_CKSUM=$(cksum $SETUP_FILE | awk '{ print $1 }')
export ORACLE_IMAGE="db-prebuilt-$SETUP_FILE_CKSUM:12.2.0.1-ee"
TEMP_CONTAINER="oracle-build-12-$(basename $SETUP_FOLDER)"

if test -z "$(docker images -q $ORACLE_IMAGE)"
then
     log "🏭 Prebuilt $ORACLE_IMAGE docker image did not exist, building it now..it can take a while..."
     log "Startup a container ${TEMP_CONTAINER} and create the database"
     docker run -d -e ORACLE_PWD=Admin123 -v ${SETUP_FOLDER}:/opt/oracle/scripts/setup --name ${TEMP_CONTAINER} ${OLD_ORACLE_IMAGE}

     # Verify ${TEMP_CONTAINER} has started within MAX_WAIT seconds
     MAX_WAIT=2500
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for ${TEMP_CONTAINER} to start"
     docker container logs ${TEMP_CONTAINER} > /tmp/out.txt 2>&1
     while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
     sleep 10
     docker container logs ${TEMP_CONTAINER} > /tmp/out.txt 2>&1
     CUR_WAIT=$(( CUR_WAIT+10 ))
     if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
          logerror "ERROR: The logs in ${TEMP_CONTAINER} container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
          exit 1
     fi
     done
     log "${TEMP_CONTAINER} has started! Check logs in /tmp/${TEMP_CONTAINER}.log"
     docker container logs ${TEMP_CONTAINER} > /tmp/${TEMP_CONTAINER}.log 2>&1
     log "Stop the running container"
     docker stop -t 600 ${TEMP_CONTAINER}
     log "Create the image with the prebuilt database"
     docker commit -m "Image with prebuilt database" ${TEMP_CONTAINER} ${ORACLE_IMAGE}
     log "Clean up ${TEMP_CONTAINER}"
     docker rm ${TEMP_CONTAINER}
fi

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

if [ ! -z "$CONNECTOR_TAG" ]
then
     JDBC_CONNECTOR_VERSION=$CONNECTOR_TAG
else
     JDBC_CONNECTOR_VERSION=$(docker run vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} cat /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/manifest.json | jq -r '.version')
fi
log "JDBC Connector version is $JDBC_CONNECTOR_VERSION"
if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     if [ ! -z "$CI" ]
     then
          # running with github actions
          aws s3 cp --only-show-errors s3://kafka-docker-playground/3rdparty/ojdbc8.jar .
     fi
     if [ ! -f ${DIR}/ojdbc8.jar ]
     then
          logerror "ERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls-db-auth.yml" down -v --remove-orphans
     log "Starting up oracle container to get generated cert from oracle server wallet"
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls-db-auth.yml" up -d oracle
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.no-ojdbc-mtls.yml" down -v --remove-orphans
     log "Starting up oracle container to get generated cert from oracle server wallet"
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.no-ojdbc-mtls.yml" up -d oracle
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
# https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf
log "Create a wallet for the test CA"

docker exec oracle bash -c "orapki wallet create -wallet /tmp/root -pwd WalletPasswd123"
# Add a self-signed certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/root -dn CN=root_test,C=US -keysize 2048 -self_signed -validity 3650 -pwd WalletPasswd123"
# Export the certificate
docker exec oracle bash -c "orapki wallet export -wallet /tmp/root -dn CN=root_test,C=US -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"

log "Create a wallet for the Oracle server"

# Create an empty wallet with auto login enabled
docker exec oracle bash -c "orapki wallet create -wallet /tmp/server -pwd WalletPasswd123 -auto_login"
# Add a user In the wallet (a new pair of private/public keys is created)
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -keysize 2048"
# Export the certificate request to a file
docker exec oracle bash -c "orapki wallet export -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -request /tmp/server/creq.txt"
# Using the test CA, sign the certificate request
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/server/creq.txt -cert /tmp/server/cert.txt -validity 3650 -pwd WalletPasswd123"
log "You now have the following files under the /tmp/server directory"
docker exec oracle ls /tmp/server
# View the signed certificate:
docker exec oracle bash -c "orapki cert display -cert /tmp/server/cert.txt -complete"
# Add the test CA's trusted certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -trusted_cert -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"
# add the user certificate to the wallet:
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -user_cert -cert /tmp/server/cert.txt -pwd WalletPasswd123"

cd ${DIR}/mtls
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
log "Create a JKS keystore"
# Create a new private/public key pair for 'CN=connect,C=US'
rm -f keystore.jks
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -genkey -alias testclient -dname 'CN=connect,C=US' -storepass 'welcome123' -storetype JKS -keystore /tmp/keystore.jks -keyalg RSA

# Generate a CSR (Certificate Signing Request):
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -certreq -alias testclient -file /tmp/csr.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Sign the client certificate using the test CA (root)
docker cp csr.txt oracle:/tmp/csr.txt
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/csr.txt -cert /tmp/cert.txt -validity 3650 -pwd WalletPasswd123"
# import the test CA's certificate:
docker cp oracle:/tmp/root/b64certificate.txt b64certificate.txt
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
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -noprompt -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Import the signed certificate
docker cp oracle:/tmp/cert.txt cert.txt
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
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testclient -file /tmp/cert.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
log "Displaying keystore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/keystore.jks -storepass 'welcome123' -v

log "Create a JKS truststore"
rm -f truststore.jks
# We import the test CA certificate
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "Displaying truststore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/truststore.jks -storepass 'welcome123' -v

cd ${DIR}

log "Alter user 'myuser' in order to be identified as 'CN=connect,C=US'"
docker exec -i oracle sqlplus sys/Admin123@//localhost:1521/ORCLPDB1 as sysdba <<- EOF
	ALTER USER myuser IDENTIFIED EXTERNALLY AS 'CN=connect,C=US';
	exit;
EOF

log "Update listener.ora, sqlnet.ora and tnsnames.ora"
docker cp ${PWD}/mtls/listener.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/listener.ora
docker cp ${PWD}/mtls/sqlnet.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/sqlnet.ora
docker cp ${PWD}/mtls/tnsnames.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/tnsnames.ora

docker exec -i oracle lsnrctl << EOF
reload
stop
start
EOF

log "Sleeping 60 seconds"
sleep 60

if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls-db-auth.yml" up -d
else
     docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.no-ojdbc-mtls.yml" up -d
fi

../../scripts/wait-for-connect-and-controlcenter.sh

sleep 10

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.oracle.net.ssl_server_dn_match": "true",
               "connection.oracle.net.authentication_services": "(TCPS)",
               "connection.url": "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLPDB1))(SECURITY=(SSL_SERVER_CERT_DN=\"CN=server,C=US\")))",
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
     http://localhost:8083/connectors/oracle-source-mtls-db-auth/config | jq .

sleep 5

log "Verifying topic oracle-CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-CUSTOMERS --from-beginning --max-messages 2


