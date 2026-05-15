#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic pg-CUSTOMERS
set -e

playground topic create --topic pg-CUSTOMERS

docker compose -f docker-compose.yml build
docker compose -f docker-compose.yml down -v --remove-orphans
docker compose -f docker-compose.yml up -d --quiet-pull

playground container logs --container ibmdb2 --wait-for-log "Setup has completed" --max-wait 600
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
db2 update dbm cfg using SSL_CIPHERSPECS TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
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
#  SSL cipher specs                      (SSL_CIPHERSPECS) = TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
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
    sudo chmod -R a+rw .
fi
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -import -trustcacerts -v -noprompt -alias myAlias -file /tmp/server.arm -keystore /tmp/truststore.jks -storepass 'confluent'
log "Displaying truststore"
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -list -keystore /tmp/truststore.jks -storepass 'confluent' -v

base64_truststore=$(cat $PWD/truststore.jks | base64 | tr -d '\n')
cd -

log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else 
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done

docker exec -i ibmdb2 bash << EOF
su - db2inst1
db2 connect to testdb user db2inst1 using passw0rd
db2 -x "CREATE TABLE CUSTOMERS(ID INT GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL,FIRST_NAME VARCHAR(50),LAST_NAME VARCHAR(50),EMAIL VARCHAR(50),GENDER VARCHAR(50),CLUB_STATUS VARCHAR(20),COMMENTS VARCHAR(90),CREATE_TS TIMESTAMP NOT NULL DEFAULT CURRENT TIMESTAMP,UPDATE_TS TIMESTAMP NOT NULL DEFAULT CURRENT TIMESTAMP,PRIMARY KEY(ID))"
db2 -x "CREATE TRIGGER T_CUSTOMERS_UPDATE_TS NO CASCADE BEFORE UPDATE ON CUSTOMERS REFERENCING NEW AS N FOR EACH ROW MODE DB2SQL SET N.UPDATE_TS = CURRENT TIMESTAMP"
EOF

docker exec -i ibmdb2 bash << EOF
su - db2inst1
db2 connect to testdb user db2inst1 using passw0rd
db2 describe table CUSTOMERS
EOF

# Column name                     schema    Data type name      Length     Scale Nulls
# ------------------------------- --------- ------------------- ---------- ----- ------
# ID                              SYSIBM    INTEGER                      4     0 No    
# FIRST_NAME                      SYSIBM    VARCHAR                     50     0 Yes   
# LAST_NAME                       SYSIBM    VARCHAR                     50     0 Yes   
# EMAIL                           SYSIBM    VARCHAR                     50     0 Yes   
# GENDER                          SYSIBM    VARCHAR                     50     0 Yes   
# CLUB_STATUS                     SYSIBM    VARCHAR                     20     0 Yes   
# COMMENTS                        SYSIBM    VARCHAR                     90     0 Yes   
# CREATE_TS                       SYSIBM    TIMESTAMP                   10     6 No    
# UPDATE_TS                       SYSIBM    TIMESTAMP                   10     6 No   

docker exec -i ibmdb2 bash << EOF
su - db2inst1
db2 connect to testdb user db2inst1 using passw0rd
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Robinet', 'Leheude', 'rleheude5@reddit.com', 'Female', 'platinum', 'Virtual upward-trending definition')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Fay', 'Huc', 'fhuc6@quantcast.com', 'Female', 'bronze', 'Operative composite capacity')"
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Patti', 'Rosten', 'prosten7@ihg.com', 'Female', 'silver', 'Integrated bandwidth-monitored instruction set')"
EOF

connector_name="IbmDb2SourceSSL_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "IbmDb2Source",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "output.data.format": "AVRO",
    "connection.host": "$NGROK_HOSTNAME",
    "connection.port": "$NGROK_PORT",
    "connection.user": "db2inst1",
    "connection.password": "passw0rd",
    "db.name": "testdb",
    "mode": "timestamp+incrementing",
    "schema.pattern": "DB2INST1",

    "timestamp.columns.mapping": ".*:[UPDATE_TS]",
    "incrementing.column.mapping": ".*:ID",
    

    "ssl.mode": "require",
    "ssl.truststorefile": "data:text/plain;base64,$base64_truststore",
    "ssl.truststorepassword": "confluent",

    "topic.prefix": "pg-",
    "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

docker exec -i ibmdb2 bash << EOF
su - db2inst1
db2 connect to testdb user db2inst1 using passw0rd
db2 -x "INSERT INTO CUSTOMERS (FIRST_NAME, LAST_NAME, EMAIL, GENDER, CLUB_STATUS, COMMENTS) VALUES ('Romy', 'Mitchell', 'rmitchell0@rambler.db', 'Female', 'bronze', 'new inserted record')"
EOF

sleep 5

log "Verifying topic pg-CUSTOMERS"
playground topic consume --topic pg-CUSTOMERS --min-expected-messages 9 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
