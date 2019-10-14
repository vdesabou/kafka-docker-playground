#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/oracle/ojdbc6.jar ]
then
     echo "ERROR: ${DIR}/oracle/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
exit 0


# echo "Describing the application table in DB 'db':"
# docker container exec oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe/;export ORACLE_SID=xe;/u01/app/oracle/product/11.2.0/xe/bin/sqlplus system/oracle "

# docker exec -i oracle export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe/;export ORACLE_SID=xe;/u01/app/oracle/product/11.2.0/xe/bin/sqlplus myuser/mypassword@//localhost:1521/XE  << EOF
# select * from departments;
# EOF

#docker container exec oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe/;export ORACLE_SID=xe;echo 'alter system disable restricted session;' | /u01/app/oracle/product/11.2.0/xe/bin/sqlplus -s SYSTEM/oracle"

exit 0

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
                    "connection.url": "jdbc:oracle:thin:@oracledb:1521/xe",
                    "table.whitelist":"MYTABLE",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"UPDATE_TS",
                    "incrementing.column.name":"ID",
                    "topic.prefix":"oracle-",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }}' \
     http://localhost:8083/connectors | jq .


docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-source3",
               "config": {
                    "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracledb:1521/xe",
                    "table.whitelist":"MYTABLE",
                    "mode":"bulk",
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


