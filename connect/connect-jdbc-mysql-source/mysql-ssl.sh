#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

cd ../../connect/connect-jdbc-mysql-source
if [ ! -f ${PWD}/mysql-connector-j-8.4.0.jar ]
then
     log "Downloading mysql-connector-j-8.4.0.jar"
     wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.4.0/mysql-connector-j-8.4.0.jar
fi
cd -
# required to make utils.sh script being able to work, do not remove:
# PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
#playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.ssl.yml" down -v --remove-orphans
log "Starting up mysql container to get generated certs from /var/lib/mysql"
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.ssl.yml" up -d mysql

sleep 5

log "Getting certs from mysql container and transform them to JKS"
mkdir -p ${PWD}/security/
rm -rf ${PWD}/security/*
# https://dev.mysql.com/doc/connector-j/5.1/en/connector-j-reference-using-ssl.html
docker cp mysql:/var/lib/mysql/ca.pem ${PWD}/security/
docker cp mysql:/var/lib/mysql/client-key.pem ${PWD}/security/
docker cp mysql:/var/lib/mysql/client-cert.pem ${PWD}/security/

log "Creating JKS from pem files"
cd ${PWD}/security/
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importcert -alias MySQLCACert -noprompt -file /tmp/ca.pem -keystore /tmp/truststore.jks -storepass mypassword
# Convert the client key and certificate files to a PKCS #12 archive
docker run --quiet --rm -v $PWD:/tmp alpine/openssl pkcs12 -export -in /tmp/client-cert.pem -inkey /tmp/client-key.pem -name "mysqlclient" -passout pass:mypassword -out /tmp/client-keystore.p12
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
# Import the client key and certificate into a Java keystore:
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importkeystore -srckeystore /tmp/client-keystore.p12 -srcstoretype pkcs12 -srcstorepass mypassword -destkeystore /tmp/keystore.jks -deststoretype JKS -deststorepass mypassword
cd -

set_profiles
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.ssl.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d --quiet-pull
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.ssl.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "plaintext"
wait_container_ready


log "Create table"
docker exec -i mysql mysql --user=root --password=password --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=mydb << EOF
USE mydb;

CREATE TABLE team (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);


INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'kafka',
  'kafka@apache.org',
  NOW()
);

ALTER TABLE team AUTO_INCREMENT = 101;
describe team;
select * from team;
EOF

log "Adding an element to the table"
docker exec -i mysql mysql --user=root --password=password --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=mydb << EOF
USE mydb;

INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'another',
  'another@apache.org',
  NOW()
);
EOF

log "Creating MySQL source connector"
playground connector create-or-update --connector mysql-ssl-source  << EOF
{
  "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max":"1",
  "connection.url": "jdbc:mysql://mysql:3306/mydb?user=userssl&password=password&verifyServerCertificate=true&useSSL=true&requireSSL=true&enabledTLSProtocols=TLSv1,TLSv1.1,TLSv1.2,TLSv1.3",
  "table.whitelist":"team",
  "mode":"timestamp+incrementing",
  "timestamp.column.name":"last_modified",
  "incrementing.column.name":"id",
  "topic.prefix":"mysql-"
}
EOF

sleep 5

log "Verifying topic mysql-team"
playground topic consume --topic mysql-team --min-expected-messages 2 --timeout 60


