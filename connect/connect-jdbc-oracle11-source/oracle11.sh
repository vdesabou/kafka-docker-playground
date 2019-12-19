#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc6.jar ]
then
     echo -e "\033[0;33mERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement\033[0m"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mCreating Oracle source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
                    "numeric.mapping":"best_fit",
                    "mode":"timestamp",
                    "poll.interval.ms":"1000",
                    "validate.non.null":"false",
                    "table.whitelist":"MYTABLE",
                    "timestamp.column.name":"UPDATE_TS",
                    "topic.prefix":"oracle-",
                    "schema.pattern":"MYUSER",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/oracle-source/config | jq .

sleep 5

echo -e "\033[0;33mVerifying topic oracle-MYTABLE\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic oracle-MYTABLE --from-beginning --max-messages 1