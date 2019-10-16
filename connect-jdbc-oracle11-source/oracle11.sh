#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc6.jar ]
then
     echo "ERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

exit 0

# FIXTHIS: not working
echo "Creating Oracle source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-source",
               "config": {
                    "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/xe",
                    "table.whitelist":"MYTABLE",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"UPDATE_TS",
                    "incrementing.column.name":"ID",
                    "topic.prefix":"oracle-",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Verifying topic oracle-mytable"
#docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic oracle-mytable --from-beginning --max-messages 2


