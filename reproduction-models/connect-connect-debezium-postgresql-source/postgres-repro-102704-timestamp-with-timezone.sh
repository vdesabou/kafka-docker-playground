#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-102704-timestamp-with-timezone.yml"


log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"

docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments, tsm) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management', '2022-04-25 12:05:54.035338+05:30');"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT tsm FROM CUSTOMERS'"

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
                    "transforms": "addTopicSuffix,unwrap",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw",
                    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .

# 2022-04-25 12:05:54.035338+05:30

sleep 5

log "Verifying topic asgard.public.customers-raw"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --max-messages 5


log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "asgard.public.customers-raw",
               "auto.create": "true",
               "table.name.format": "out",
               "transforms": "T1",
               "transforms.T1.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
               "transforms.T1.target.type": "Timestamp",
               "transforms.T1.field": "tsm",
               "transforms.T1.format": "yyyy-MM-dd HH:mm:ss.SSSSSSX"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .

log "Show content of OUT table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT tsm FROM OUT'"

#            tsm           
# -------------------------
#  2022-04-25 07:06:29.338
#  2022-04-25 07:06:29.338
#  2022-04-25 07:06:29.338
#  2022-04-25 07:06:29.338
#  2022-04-25 07:06:29.338
#  2022-04-25 07:06:29.338

# [2022-04-28 13:11:48,209] INFO [postgres-sink|task-0] Setting metadata for table "out" to Table{name='"out"', type=TABLE columns=[Column{'first_name', isPrimaryKey=false, allowsNull=true, sqlType=text}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'comments', isPrimaryKey=false, allowsNull=true, sqlType=text}, Column{'tsm', isPrimaryKey=false, allowsNull=true, sqlType=timestamp}, Column{'email', isPrimaryKey=false, allowsNull=true, sqlType=text}, Column{'create_ts', isPrimaryKey=false, allowsNull=true, sqlType=int8}, Column{'club_status', isPrimaryKey=false, allowsNull=true, sqlType=text}, Column{'last_name', isPrimaryKey=false, allowsNull=true, sqlType=text}, Column{'update_ts', isPrimaryKey=false, allowsNull=true, sqlType=int8}, Column{'gender', isPrimaryKey=false, allowsNull=true, sqlType=text}]} (io.confluent.connect.jdbc.util.TableDefinitions:64)
