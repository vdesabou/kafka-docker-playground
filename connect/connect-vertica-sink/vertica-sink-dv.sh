#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-9.3.1-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/9.3.x/9.3.1-0/vertica-client-9.3.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-9.3.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-9.3.1-0.x86_64.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Create the table and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE TABLE url_override_normalized
(
    dwhCreationDate timestamp DEFAULT (statement_timestamp())::timestamp,
    kafkaId int NOT NULL,
    ListID int,
    KafkaKeyIsDeleted boolean DEFAULT true
);
EOF

#     NormalizedUrlHash int,
#     URL varchar(80),
sleep 2

log "Sending messages to topic url_override_normalized"

# seq -f "{\"ListID\": 1,\"kafkaId\": 1}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic url_override_normalized --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"ListID","type":"int"},{"name":"kafkaId","type":"int"}]}'

# to reproduce some rejected messages
seq -f "{\"ListID\": null,\"kafkaId\": 1}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic url_override_normalized --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"ListID", "type": ["null", "long"], "default": null},{"name":"kafkaId","type":"int"}]}'

log "Creating Vertica sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.vertica.VerticaSinkConnector",
                    "tasks.max" : "1",
                    "vertica.database": "docker",
                    "vertica.host": "vertica",
                    "vertica.port": "5433",
                    "vertica.username": "dbadmin",
                    "vertica.password": "",
                    "vertica.load.method": "DIRECT",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true",
                    "topics": "url_override_normalized",
                    "pk.mode": "record_key",
                    "pk.fields": "kafkaId",
                    "enable.auto.commit": "false",
                    "transforms": "insert_isKafkaDeleted, cast_isKafkaDeleted_toBoolean, insert_dwhCreateDate",
                    "transforms.insert_isKafkaDeleted.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.insert_isKafkaDeleted.static.field": "KafkaKeyIsDeleted",
                    "transforms.insert_isKafkaDeleted.static.value": "0",
                    "transforms.cast_isKafkaDeleted_toBoolean.type": "org.apache.kafka.connect.transforms.Cast$Value",
                    "transforms.cast_isKafkaDeleted_toBoolean.spec": "KafkaKeyIsDeleted:boolean",
                    "transforms.insert_dwhCreateDate.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.insert_dwhCreateDate.timestamp.field": "dwhCreationDate",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter" : "Avro",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq_docker_cli .

                    # "transforms.timestampconverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
                    # "transforms.timestampconverter.field": "dwhCreationDate",
                    # "transforms.timestampconverter.target.type": "Timestamp",

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.url_override_normalized;
EOF

#      dwhCreationDate     | kafkaId | ListID | KafkaKeyIsDeleted
# -------------------------+---------+--------+-------------------
#  2020-01-17 16:26:53.087 |       1 |      1 | f
#  2020-01-17 16:26:53.102 |       1 |      1 | f
#  2020-01-17 16:26:53.103 |       1 |      1 | f
#  2020-01-17 16:26:53.103 |       1 |      1 | f
#  2020-01-17 16:26:53.103 |       1 |      1 | f
#  2020-01-17 16:26:53.103 |       1 |      1 | f
#  2020-01-17 16:26:53.103 |       1 |      1 | f
#  2020-01-17 16:26:53.104 |       1 |      1 | f
#  2020-01-17 16:26:53.104 |       1 |      1 | f
#  2020-01-17 16:26:53.104 |       1 |      1 | f
# (10 rows)

# Without trace logs:

# [2020-01-17 17:01:39,840] INFO Wrote 10 record(s) to stream (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,840] INFO Waiting for import to complete. (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,850] INFO put() - Imported 10 record(s) in 42 millisecond(s). (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN put() - Rejected 10 record(s). (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 1 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 2 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 3 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 4 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 5 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 6 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 7 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 8 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 9 (io.confluent.vertica.VerticaSinkTask)
# [2020-01-17 17:01:39,851] WARN Rejected row 10 (io.confluent.vertica.VerticaSinkTask)