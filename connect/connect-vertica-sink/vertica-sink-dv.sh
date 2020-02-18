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

# if [ ! -f ${DIR}/vertica-jdbc.jar ]
# then
#      # install deps
#      log "Getting vertica-jdbc.jar from vertica-client-9.2.1-0.x86_64.tar.gz"
#      wget https://www.vertica.com/client_drivers/9.2.x/9.2.1-0/vertica-client-9.2.1-0.x86_64.tar.gz
#      tar xvfz ${DIR}/vertica-client-9.2.1-0.x86_64.tar.gz
#      cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
#      rm -rf ${DIR}/opt
#      rm -f ${DIR}/vertica-client-9.2.1-0.x86_64.tar.gz
# fi

# if [ ! -f ${DIR}/vertica-jdbc.jar ]
# then
#      # install deps
#      log "Getting vertica-jdbc.jar from vertica-client-7.2.3-0.x86_64.tar.gz"
#      wget https://www.vertica.com/client_drivers/7.2.x/7.2.3-0/vertica-client-7.2.3-0.x86_64.tar.gz
#      tar xvfz ${DIR}/vertica-client-7.2.3-0.x86_64.tar.gz
#      cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
#      rm -rf ${DIR}/opt
#      rm -f ${DIR}/vertica-client-7.2.3-0.x86_64.tar.gz
# fi

if [ ! -f ${DIR}/producer/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer"
     docker run -it --rm -e TAG=$TAG -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

if [ ! -f ${DIR}/KeyToValue/target/KeyToValue-1.0.0-SNAPSHOT.jar ]
then
     # build KeyToValue transform
     log "Build KeyToValue transform"
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/KeyToValue":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/KeyToValue/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

if [ ! -f ${DIR}/TombstoneToNull/target/TombstoneToNull-1.0.0-SNAPSHOT.jar ]
then
     # build TombstoneToNull transform
     log "Build TombstoneToNull transform"
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/TombstoneToNull":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/TombstoneToNull/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

if [ ! -f ${DIR}/vertica-stream-writer/target/vertica-stream-writer-0.0.1-SNAPSHOT.jar ]
then
     log "Build vertica-stream-writer-0.0.1-SNAPSHOT.jar"
     git clone https://github.com/jcustenborder/vertica-stream-writer.git
     cp ${DIR}/QueryBuilder.java vertica-stream-writer/src/main/java/com/github/jcustenborder/vertica/QueryBuilder.java
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/vertica-stream-writer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/vertica-stream-writer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-dv.yml"


log "Create the table customer1"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE TABLE public.customer1
(
    dwhCreationDate timestamp DEFAULT (statement_timestamp())::timestamp,
    kafkaId int NOT NULL,
    ListID int,
    NormalizedHashItemID int,
    KafkaKeyIsDeleted boolean DEFAULT true,
    MyFloatValue float,
    MyTimestamp timestamp NOT NULL
);
EOF

log "Create the table customer2"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE TABLE public.customer2
(
    dwhCreationDate timestamp DEFAULT (statement_timestamp())::timestamp,
    kafkaId int NOT NULL,
    ListID int,
    NormalizedHashItemID int,
    KafkaKeyIsDeleted boolean DEFAULT true,
    MyFloatValue float,
    MyTimestamp timestamp NOT NULL
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
                    "transforms": "TombstoneToNull, insert_dwhCreateDate, KeyToValue, cast_kafkaId_toInt, mapMyTableFieldToTopic,MyTimestamp_convert",
                    "transforms.TombstoneToNull.type": "com.github.vdesabou.kafka.connect.transforms.TombstoneToNull",
                    "transforms.insert_dwhCreateDate.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.insert_dwhCreateDate.timestamp.field": "dwhCreationDate",
                    "transforms.KeyToValue.type": "com.github.vdesabou.kafka.connect.transforms.KeyToValue",
                    "transforms.KeyToValue.key.field.name":"kafkaId",
                    "transforms.cast_kafkaId_toInt.type": "org.apache.kafka.connect.transforms.Cast$Value",
                    "transforms.cast_kafkaId_toInt.spec": "kafkaId:int64",
                    "transforms.mapMyTableFieldToTopic.type": "io.confluent.connect.transforms.ExtractTopic$Value",
                    "transforms.mapMyTableFieldToTopic.field": "MyTable",
                    "transforms.MyTimestamp_convert.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
                    "transforms.MyTimestamp_convert.field": "MyTimestamp",
                    "transforms.MyTimestamp_convert.target.type": "Timestamp",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "vertica.load.method": "DIRECT",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica for customer1"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer1;
EOF

log "Check data is in Vertica for customer2"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer2;
EOF

#      dwhCreationDate     | kafkaId | ListID | NormalizedHashItemID | URL  | KafkaKeyIsDeleted
# -------------------------+---------+--------+----------------------+------+-------------------
#  2020-01-22 14:41:36.121 |       0 |      0 |                    0 | url  | f
#  2020-01-22 14:41:36.667 |       1 |      1 |                    1 | url  | f
#  2020-01-22 14:41:37.172 |       2 |      0 |                    0 | null | t    <--- tombstone
#  2020-01-22 14:41:37.679 |       3 |      3 |                    3 | url  | f
#  2020-01-22 14:41:38.185 |       4 |      4 |                    4 | url  | f
#  2020-01-22 14:41:38.69  |       5 |      5 |                    5 | url  | f


log "Check for rejected data for customer1"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer1_rej;
EOF

log "Check for rejected data for customer2"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer2_rej;
EOF

docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from columns;
EOF

docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from tables;
EOF

docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
SELECT c.column_name, c.data_type, c.data_type_length, c.numeric_precision, c.numeric_scale FROM columns c INNER JOIN tables t ON c.table_id = t.table_id WHERE upper(t.table_name) = upper('customer1') ORDER BY c.ordinal_position;
EOF

#      node_name     |      file_name      |         session_id         |  transaction_id   | statement_id | batch_number | row_number |                                              rejected_data                                              | rejected_data_orig_length |                          rejected_reason
# -------------------+---------------------+----------------------------+-------------------+--------------+--------------+------------+---------------------------------------------------------------------------------------------------------+---------------------------+--------------------------------------------------------------------
#  v_docker_node0001 | STDIN (Batch No. 1) | v_docker_node0001-109:0x17 | 45035996273705370 |           10 |            0 |         12 | ����@_ultralongurlultralongurlultralongurlultralongurlultralongurlultralongurlultralongurultralongurl |                       132 | The 95-byte value is too long for type Varchar(80), column 5 (URL)
# (1 row)

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