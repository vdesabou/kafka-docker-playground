#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/ojdbc8.jar ]
then
     logerror "ERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

if [ -z "$TRAVIS" ]
then
     # not running with travis
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
if [ ! -z "$TRAVIS" ]
then
     # if this is travis build, use private image.
     export ORACLE_IMAGE="vdesabou/oracle12"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


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
     echo -e "\nERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

log "Creating Oracle sink connector"

docker exec connect \
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
                    "auto.evolve":"true"
          }' \
     http://localhost:8083/connectors/oracle-sink/config | jq_docker_cli .


log "Sending messages to topic ORDERS"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5


log "Show content of ORDERS table:"
docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus myuser/mypassword@//localhost:1521/ORCLPDB1"

