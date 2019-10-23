#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating MySQL sink connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "mysql-sink",
               "config": {
                    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "topics": "orders",
                    "auto.create": "true"
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic orders"
docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5


echo "Describing the orders table in DB 'db':"
docker container exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe orders'"

echo "Show content of orders table:"
docker container exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from orders'"


