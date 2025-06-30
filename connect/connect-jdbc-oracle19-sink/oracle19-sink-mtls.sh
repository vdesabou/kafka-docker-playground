#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-jdbc-oracle19-sink/ora-setup-scripts"

# required to make utils.sh script being able to work, do not remove:
# PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
#playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.mtls.yml" down -v --remove-orphans
log "Starting up oracle container to get generated cert from oracle server wallet"
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.mtls.yml" up -d oracle


playground container logs --container oracle --wait-for-log "DATABASE IS READY TO USE" --max-wait 600
log "Oracle DB has started!"
log "Setting up Oracle Database Prerequisites"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     CREATE USER  C##MYUSER IDENTIFIED BY mypassword;
     GRANT CONNECT TO  C##MYUSER;
     GRANT CREATE SESSION TO  C##MYUSER;
     GRANT CREATE TABLE TO  C##MYUSER;
     GRANT CREATE SEQUENCE TO  C##MYUSER;
     GRANT CREATE TRIGGER TO  C##MYUSER;
     ALTER USER  C##MYUSER QUOTA 100M ON users;
     exit;
EOF

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
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -genkey -alias testclient -dname 'CN=connect,C=US' -storepass 'welcome123' -storetype JKS -keystore /tmp/keystore.jks -keyalg RSA

# Generate a CSR (Certificate Signing Request):
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -certreq -alias testclient -file /tmp/csr.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
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
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -import -v -noprompt -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
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
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -import -v -alias testclient -file /tmp/cert.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
log "Displaying keystore"
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -list -keystore /tmp/keystore.jks -storepass 'welcome123' -v

log "Create a JKS truststore"
rm -f truststore.jks
# We import the test CA certificate
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "Displaying truststore"
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -list -keystore /tmp/truststore.jks -storepass 'welcome123' -v

cd ${DIR}

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

set_profiles
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.mtls.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d --quiet-pull
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${PWD}/docker-compose.plaintext.mtls.yml ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "plaintext"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"

wait_container_ready

sleep 10

log "Creating Oracle sink connector"

playground connector create-or-update --connector oracle-sink-mtls  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.user": "C##MYUSER",
  "connection.password": "mypassword",
  "connection.oracle.net.ssl_server_dn_match": "true",
  "connection.url": "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLCDB))(SECURITY=(SSL_SERVER_CERT_DN=\"CN=server,C=US\")))",
  "connection.javax.net.ssl.trustStore": "/tmp/truststore.jks",
  "connection.javax.net.ssl.trustStorePassword": "welcome123",
  "connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
  "connection.javax.net.ssl.keyStorePassword": "welcome123",
  "topics": "ORDERS",
  "auto.create": "true",
  "insert.mode":"insert",
  "auto.evolve":"true"
}
EOF


log "Sending messages to topic ORDERS"
playground topic produce -t ORDERS --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

playground topic produce -t ORDERS --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

sleep 10

log "Show content of ORDERS table:"
docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus C##MYUSER/mypassword@//localhost:1521/ORCLCDB" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log

