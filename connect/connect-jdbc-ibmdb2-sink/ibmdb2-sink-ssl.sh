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

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.ssl.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} down -v --remove-orphans
log "Starting up ibmdb2 container to get db2jcc4.jar"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.ssl.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d ibmdb2

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

log "Enable SSL on DB2"
# https://stackoverflow.com/questions/63024640/db2-in-docker-container-problem-with-autostart-of-ssl-configuration-after-resta
# https://medium.datadriveninvestor.com/configuring-secure-sockets-layer-ssl-for-db2-server-and-client-3b317a033d71
docker exec -i ibmdb2 bash << EOF
su - db2inst1
gsk8capicmd_64 -keydb -create -db "server.kdb" -pw "confluent" -stash
gsk8capicmd_64 -cert -create -db "server.kdb" -pw "confluent" -label "myLabel" -dn "CN=ibmdb2" -size 2048 -sigalg SHA256_WITH_RSA
gsk8capicmd_64 -cert -extract -db "server.kdb" -pw "confluent" -label "myLabel" -target "server.arm" -format ascii -fips
gsk8capicmd_64 -cert -details -db "server.kdb" -pw "confluent" -label "myLabel"
db2 update dbm cfg using SSL_SVR_KEYDB /database/config/db2inst1/server.kdb
db2 update dbm cfg using SSL_SVR_STASH /database/config/db2inst1/server.sth
db2 update dbm cfg using SSL_SVCENAME 50002
db2 update dbm cfg using SSL_VERSIONS TLSv12
db2 update dbm cfg using SSL_SVR_LABEL myLabel
db2set -i db2inst1 DB2COMM=SSL,TCPIP
db2stop force
db2start
EOF

log "verifying DB2 SSL config"
docker exec -i ibmdb2 bash << EOF
su - db2inst1
gsk8capicmd_64 -cert -list -db "server.kdb" -stashed
db2 get dbm cfg|grep SSL
EOF
#-       myLabel
#  SSL server keydb file                   (SSL_SVR_KEYDB) = /database/config/db2inst1/server.kdb
#  SSL server stash file                   (SSL_SVR_STASH) = /database/config/db2inst1/server.sth
#  SSL server certificate label            (SSL_SVR_LABEL) = myLabel
#  SSL service name                         (SSL_SVCENAME) = 50002
#  SSL cipher specs                      (SSL_CIPHERSPECS) = 
#  SSL versions                             (SSL_VERSIONS) = TLSv12
#  SSL client keydb file                  (SSL_CLNT_KEYDB) = 
#  SSL client stash file                  (SSL_CLNT_STASH) = 

mkdir -p ${PWD}/security/
rm -rf ${PWD}/security/*

cd ${PWD}/security/
docker cp ibmdb2:/database/config/db2inst1/server.arm .

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
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -trustcacerts -v -noprompt -alias myAlias -file /tmp/server.arm -keystore /tmp/truststore.jks -storepass 'confluent'
log "Displaying truststore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/truststore.jks -storepass 'confluent' -v
cd -


docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.ssl.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d

../../scripts/wait-for-connect-and-controlcenter.sh

# Keep it for utils.sh
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.ssl.yml"

log "Sending messages to topic ORDERS"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"ID","type":"int"},{"name":"PRODUCT", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

log "Creating JDBC IBM DB2 sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url":"jdbc:db2://ibmdb2:50002/sample:retrieveMessagesFromServerOnGetMessage=true;sslConnection=true;sslTrustStoreLocation=/etc/kafka/secrets/truststore.jks;sslTrustStorePassword=confluent;sslTrustStoreType=JKS;",
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

