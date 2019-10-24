#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc6.jar ]
then
     echo "ERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# select owner,
#        object_name
# from dba_objects
# where object_name = any ('ORDERS','orders');

# SELECT owner
# FROM all_objects
# WHERE object_type IN ('TABLE','VIEW')
# AND object_name = 'orders';

# select orders from all_tables where owner = 'MYUSER';

# grant select on orders to myuser;

echo "Creating JDBC Oracle sink connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-sink2",
               "config": {
                    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
                    "topics": "ORDERS",
                    "auto.create": "true"
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic orders"
docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5


echo "Show content of ORDERS table:"
docker container exec oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe/;export ORACLE_SID=xe;echo 'select * from ORDERS;' | /u01/app/oracle/product/11.2.0/xe/bin/sqlplus myuser/mypassword@//localhost:1521/XE"


