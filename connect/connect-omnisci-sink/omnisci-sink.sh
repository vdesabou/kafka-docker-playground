#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic orders"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
 "type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF


echo "Creating OmniSci sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.omnisci.OmnisciSinkConnector",
                    "tasks.max" : "1",
                    "topics": "orders",
                    "connection.database": "omnisci",
                    "connection.port": "6274",
                    "connection.host": "omnisci",
                    "connection.user": "admin",
                    "connection.password": "HyperInteractive",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/omnisci-sink/config | jq .

sleep 10

echo "Verify data is in OmniSci"
docker exec -i omnisci /omnisci/bin/omnisql -p HyperInteractive << EOF
select * from orders;
EOF
