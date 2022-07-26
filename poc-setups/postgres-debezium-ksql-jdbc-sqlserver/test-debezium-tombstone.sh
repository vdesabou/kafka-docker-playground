#!/bin/bash
set -x

#
# use with playbook: https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-postgresql-source
#

echo "Deleting customer 11 "
docker exec postgres bash -c "psql -U myuser -d postgres -c 'delete FROM CUSTOMERS where id=11'"

echo "Showing CDC messages"
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --property key.separator=" : " --timeout-ms 5000

echo "Re-deploying Debezium PostgreSQL source connector without tombstones"
curl --silent -X PUT \
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
                    "transforms.addTopicSuffix.replacement":"$1-raw",
                    "tombstones.on.delete":"false"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .

sleep 5


echo "Deleting customer 12"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'delete FROM CUSTOMERS where id=12'"

echo "Showing CDC messages"
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --property key.separator=" : " --timeout-ms 5000

