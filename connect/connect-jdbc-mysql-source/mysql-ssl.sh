#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.ssl.yml" down -v --remove-orphans
log "Starting up mysql container to get generated certs from /var/lib/mysql"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.ssl.yml" up -d mysql

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
if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -importcert -alias MySQLCACert -noprompt -file /tmp/ca.pem -keystore /tmp/truststore.jks -storepass mypassword
# Convert the client key and certificate files to a PKCS #12 archive
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl pkcs12 -export -in /tmp/client-cert.pem -inkey /tmp/client-key.pem -name "mysqlclient" -passout pass:mypassword -out /tmp/client-keystore.p12
# Import the client key and certificate into a Java keystore:
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -importkeystore -srckeystore /tmp/client-keystore.p12 -srcstoretype pkcs12 -srcstorepass mypassword -destkeystore /tmp/keystore.jks -deststoretype JKS -deststorepass mypassword
cd -

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.ssl.yml" up -d
../../scripts/wait-for-connect-and-controlcenter.sh


log "Describing the application table in DB 'db':"
docker exec mysql bash -c "mysql --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=db -e 'describe application'"

log "Show content of application table:"
docker exec mysql bash -c "mysql --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=db -e 'select * from application'"

log "Adding an element to the table"
docker exec mysql mysql --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=db -e "
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "

log "Show content of application table:"
docker exec mysql bash -c "mysql --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=db -e 'select * from application'"

log "Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"10",
               "connection.url": "jdbc:mysql://mysql:3306/db?user=userssl&password=password&verifyServerCertificate=true&useSSL=true&requireSSL=true&enabledTLSProtocols=TLSv1,TLSv1.1,TLSv1.2,TLSv1.3",
               "table.whitelist":"application",
               "mode":"timestamp+incrementing",
               "timestamp.column.name":"last_modified",
               "incrementing.column.name":"id",
               "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-ssl-source/config | jq .

sleep 5

log "Verifying topic mysql-application"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mysql-application --from-beginning --max-messages 2


