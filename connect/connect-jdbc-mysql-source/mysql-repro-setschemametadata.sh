#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Register a subject with version 1 (default for name=1)"
docker container exec schema-registry \
curl -X POST --silent http://localhost:8081/subjects/mysql-application-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"application\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\",\"default\":\"1\"},{\"name\":\"team_email\",\"type\":\"string\"},{\"name\":\"last_modified\",\"type\":{\"type\":\"long\",\"connect.version\":1,\"connect.name\":\"org.apache.kafka.connect.data.Timestamp\",\"logicalType\":\"timestamp-millis\"}}],\"connect.name\":\"application\"}"
}'

log "Register a subject with version 2 (default for name=2)"
docker container exec schema-registry \
curl -X POST --silent http://localhost:8081/subjects/mysql-application-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"application\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\",\"default\":\"2\"},{\"name\":\"team_email\",\"type\":\"string\"},{\"name\":\"last_modified\",\"type\":{\"type\":\"long\",\"connect.version\":1,\"connect.name\":\"org.apache.kafka.connect.data.Timestamp\",\"logicalType\":\"timestamp-millis\"}}],\"connect.name\":\"application\"}"
}'

log "Describing the application table in DB 'db':"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe application'"

log "Show content of application table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

log "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=db -e "
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "

log "Show content of application table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

log "Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"10",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-",
                    "transforms": "SetSchemaMetadata",
                    "transforms.SetSchemaMetadata.type": "org.apache.kafka.connect.transforms.SetSchemaMetadata$Value",
                    "transforms.SetSchemaMetadata.schema.name": "application",
                    "transforms.SetSchemaMetadata.schema.version": "1"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .

sleep 5

log "Verifying topic mysql-application"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mysql-application --from-beginning --max-messages 2


