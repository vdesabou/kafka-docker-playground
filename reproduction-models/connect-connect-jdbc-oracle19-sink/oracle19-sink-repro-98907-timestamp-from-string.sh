#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-repro-98907
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-jdbc-oracle19-sink/ora-setup-scripts"

if [ ! -z "$CONNECTOR_TAG" ]
then
     JDBC_CONNECTOR_VERSION=$CONNECTOR_TAG
else
     JDBC_CONNECTOR_VERSION=$(docker run vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} cat /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/manifest.json | jq -r '.version')
fi
log "JDBC Connector version is $JDBC_CONNECTOR_VERSION"
if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     get_3rdparty_file "ojdbc8.jar"
     if [ ! -f ${DIR}/ojdbc8.jar ]
     then
          logerror "ERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-ojdbc.repro-98907-timestamp-from-string.yml"
fi


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
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

log "Creating Oracle sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.user": "myuser",
               "connection.password": "mypassword",
               "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLPDB1",
               "topics": "ORDERS",
               "auto.create": "true",
               "insert.mode":"insert",
               "auto.evolve":"true",
               "transforms": "flatten,timestampconversion",
               "transforms.timestampconversion.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
               "transforms.timestampconversion.target.type": "Timestamp",
               "transforms.timestampconversion.format": "yyyy-MM-dd HH:mm:ss.SSS",
               "transforms.timestampconversion.field": "tsm",
               "transforms.flatten.type": "org.apache.kafka.connect.transforms.Flatten$Value",
               "transforms.flatten.delimiter": "."
          }' \
     http://localhost:8083/connectors/oracle-sink/config | jq .


log "✨ Run the avro java producer which produces to topic ORDERS"
docker exec producer-repro-98907 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 5
log "DESCRIBE ORDERS table:"
docker exec oracle bash -c "echo 'describe ORDERS;' | sqlplus myuser/mypassword@//localhost:1521/ORCLPDB1" > /tmp/result.log  2>&1
cat /tmp/result.log

# SQL>  Name                                         Null?    Type
# ----------------------------------------- -------- ----------------------------
# tsm                                       NOT NULL TIMESTAMP(6)
# quantity                                  NOT NULL NUMBER(10)
# account.bank                              NOT NULL CLOB

log "Show content of ORDERS table:"
docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus myuser/mypassword@//localhost:1521/ORCLPDB1" > /tmp/result.log  2>&1
cat /tmp/result.log


# SQL> 
# tsm
# --------------------------------------------------------------------------------
#   quantity
# ----------
# account.bank
# --------------------------------------------------------------------------------
# 2022-10-27 23:59:59.999
#       1000
# My bank

