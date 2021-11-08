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
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-ojdbc.yml"
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

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLPDB1",
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
     http://localhost:8083/connectors/oracle-source/config | jq .


sleep 5

log "Verifying topic oracle-CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-CUSTOMERS --from-beginning --max-messages 2


