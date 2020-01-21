#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "mvn"

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

if [ ! -f ${DIR}/KeyToValue/target/KeyToValue-1.0-SNAPSHOT.jar ]
then
     # build KeyToValue transform
     log "Build KeyToValue transform"
     mvn -f ${DIR}/KeyToValue/pom.xml install -DskipTests
fi

if [ ! -f ${DIR}/TombstoneToNull/target/TombstoneToNull-1.0-SNAPSHOT.jar ]
then
     # build TombstoneToNull transform
     log "Build TombstoneToNull transform"
     mvn -f ${DIR}/TombstoneToNull/pom.xml install -DskipTests
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-dv.yml"


log "Create the table and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE TABLE customer
(
    dwhCreationDate timestamp DEFAULT (statement_timestamp())::timestamp,
    kafkaId int NOT NULL,
    ListID int,
    NormalizedHashItemID int,
    URL varchar(80),
    KafkaKeyIsDeleted boolean DEFAULT true
);
EOF

sleep 2

log "Sending messages to topic customer (done using JAVA producer)"

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
                    "topics": "customer",
                    "enable.auto.commit": "false",
                    "consumer.override.max.poll.records": "501",
                    "transforms": "TombstoneToNull, insert_isKafkaDeleted, cast_isKafkaDeleted_toBoolean, insert_dwhCreateDate, KeyToValue, cast_kafkaId_toInt",
                    "transforms.TombstoneToNull.type": "com.github.vdesabou.kafka.connect.transforms.TombstoneToNull",
                    "transforms.insert_isKafkaDeleted.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.insert_isKafkaDeleted.static.field": "KafkaKeyIsDeleted",
                    "transforms.insert_isKafkaDeleted.static.value": "0",
                    "transforms.cast_isKafkaDeleted_toBoolean.type": "org.apache.kafka.connect.transforms.Cast$Value",
                    "transforms.cast_isKafkaDeleted_toBoolean.spec": "KafkaKeyIsDeleted:boolean",
                    "transforms.insert_dwhCreateDate.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.insert_dwhCreateDate.timestamp.field": "dwhCreationDate",
                    "transforms.KeyToValue.type": "com.github.vdesabou.kafka.connect.transforms.KeyToValue",
                    "transforms.KeyToValue.key.field.name":"kafkaId",
                    "transforms.cast_kafkaId_toInt.type": "org.apache.kafka.connect.transforms.Cast$Value",
                    "transforms.cast_kafkaId_toInt.spec": "kafkaId:int64",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq_docker_cli .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer;
EOF

#      dwhCreationDate     | kafkaId | ListID | NormalizedHashItemID | URL  | KafkaKeyIsDeleted
# -------------------------+---------+--------+----------------------+------+-------------------
#  2020-01-21 16:22:31.784 |       0 |      0 |                    0 | url  | f
#  2020-01-21 16:22:31.886 |       1 |      1 |                    1 | url  | f
#  2020-01-21 16:22:31.941 |       2 |      0 |                    0 | null | f     <----- tombstone
#  2020-01-21 16:22:32.001 |       3 |      3 |                    3 | url  | f
#  2020-01-21 16:22:32.058 |       4 |      4 |                    4 | url  | f
#  2020-01-21 16:22:32.116 |       5 |      5 |                    5 | url  | f
#  2020-01-21 16:22:32.173 |       6 |      6 |                    6 | url  | f


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