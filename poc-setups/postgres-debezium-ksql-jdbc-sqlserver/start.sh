#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating JDBC SQL Server (with JTDS driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "topics": "customers_flat",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Creating Debezium PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "myuser",
                    "database.password": "mypassword",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .

sleep 5

log "Setting up ksqldb pipeline"
docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 <<-EOF
CREATE STREAM customers_raw
WITH (
    KAFKA_TOPIC = 'asgard.public.customers-raw',
    VALUE_FORMAT = 'AVRO'
);

CREATE STREAM CUSTOMERS_FLAT
AS SELECT after->id as id,
          after->first_name as first_name,
          after->last_name as last_name
--           after->email as email,
--           after->gender as gender,
--           after->club_status as club_status,
--           after->comments as comments
   FROM CUSTOMERS_RAW EMIT CHANGES;
EOF