#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc8.jar ]
then
     echo "ERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

if test -z "$(docker images -q oracle/database:12.2.0.1-ee)"
then
     if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
     then
          echo "ERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     echo "Building oracle/database:12.2.0.1-ee docker image..it can take a while...(more than 15 minutes!)"
     OLDDIR=$PWD
     rm -rf ${DIR}/docker-images
     git clone https://github.com/oracle/docker-images.git

     cp ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
     cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
     ./buildDockerImage.sh -v 12.2.0.1 -e
     rm -rf ${DIR}/docker-images
     cd ${OLDDIR}
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
echo "Waiting up to $MAX_WAIT seconds for Oracle DB to start"
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
echo "Oracle DB has started!"

echo "Creating Oracle source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-source",
               "config": {
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
          }}' \
     http://localhost:8083/connectors | jq .


sleep 5

echo "Verifying topic oracle-CUSTOMERS"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic oracle-CUSTOMERS --from-beginning --max-messages 2


