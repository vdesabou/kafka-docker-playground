#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
DOMAIN=${1:-cluster-name.cluster-id.region.redshift.amazonaws.com}
PASSWORD=${2:-myPassword1}

if [ ! -f ${DIR}/RedshiftJDBC4-1.2.20.1043.jar ]
then
     wget https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/1.2.20.1043/RedshiftJDBC4-1.2.20.1043.jar
fi


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic orders"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

echo "Creating AWS Redshift Logs Source connector"
docker exec -e PROJECT="$DOMAIN" -e DATASET="$PASSWORD" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "redshift-sink",
               "config": {
                    "connector.class": "io.confluent.connect.aws.redshift.RedshiftSinkConnector",
                    "tasks.max": "1",
                    "topics": "orders",
                    "aws.redshift.domain": "'"$DOMAIN"'",
                    "aws.redshift.port": "5439",
                    "aws.redshift.database": "dev",
                    "aws.redshift.user": "awsuser",
                    "aws.redshift.password": "'"$PASSWORD"'",
                    "auto.create": "true",
                    "pk.mode": "kafka",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Verify data is in Redshift"
docker run -i debezium/postgres:10 psql -h redshift-cluster-1.cstl0cpyeuel.us-east-1.redshift.amazonaws.com -U awsuser -d dev -p 5439 << EOF
$PASSWORD
SELECT * from orders;
EOF
