#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-10.0.1-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/10.0.x/10.0.1-0/vertica-client-10.0.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
fi

if [ ! -f ${DIR}/EmptySchema/target/EmptySchema-1.0.0-SNAPSHOT.jar ]
then
     # build EmptySchema transform
     log "Build EmptySchema transform"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/EmptySchema":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/EmptySchema/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

if [ ! -f ${DIR}/producer/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer"
     docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi



${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-dv.yml"

docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE SCHEMA IF NOT EXISTS DV_DWH;
CREATE TABLE DV_DWH.customer
(
    ListID int,
    NormalizedHashItemID int,
    URL varchar,
    MyFloatValue float
);
EOF

log "Sending messages to topic customer (done using JAVA producer)"

sleep 60

# docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic customer --partition 0 --offset 3 --property print.key=true print.value=false --max-messages 1

log "Creating Vertica sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "connector.class": "io.confluent.vertica.VerticaSinkConnector",
               "errors.log.include.messages": "true",
               "tasks.max": "1",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "errors.log.enable": "true",
               "key.converter": "Long",
               "topics": "customer",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "value.converter.schemas.enable": "true",
               "vertica.database": "docker",
               "vertica.host": "vertica",
               "vertica.port": "5433",
               "vertica.username": "dbadmin",
               "vertica.password": "",
               "vertica.buffer.size.bytes" : 10285760,
               "config.action.reload": "restart",
               "rejected.record.logging.mode": "log",
               "table.name.format": "DV_DWH.${topic}",
               "auto.create": "false",
               "auto.evolve": "false",
               "vertica.load.method": "direct",
               "rejected.record.logging.mode": "table",
               "rejected.record.table.schema":"DV_EXTERNAL",
               "rejected.record.table.suffix":"_rejected_${yyyyMMdd}",
               "vertica.timeout.ms":180000,
               "consumer.override.max.poll.records":1000000,
               "consumer.override.fetch.min.bytes":1250000,
               "consumer.override.request.timeout.ms":125000000,
               "consumer.override.fetch.max.wait.ms":180000,
               "consumer.override.max.partition.fetch.bytes":125000000,
               "consumer.override.session.timeout.ms": 180000,
               "consumer.override.receive.buffer.bytes":125000000,
               "consumer.override.max.poll.interval.ms":125000000
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .

sleep 30

log "Check data is in Vertica for customer1"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from DV_DWH.customer;
EOF

# docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
# SELECT c.column_name,c.data_type,c.data_type_length,c.numeric_precision,c.numeric_scale,c.is_nullable,c.column_default FROM columns c INNER JOIN tables t ON c.table_id = t.table_id WHERE c.table_schema = 'public' AND t.table_name = 'customer'  ORDER BY c.ordinal_position;
# EOF

# 1.0.2

# 11 SECONDS

# 1.2.0

# 2800 SECONDS

# log "Check for rejected data for customer1"
# docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
# select * from public.customer1_rejected;
# EOF

# docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
# select * from columns;
# EOF

# docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
# select * from tables;
# EOF

# docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
# SELECT c.column_name, c.data_type, c.data_type_length, c.numeric_precision, c.numeric_scale FROM columns c INNER JOIN tables t ON c.table_id = t.table_id WHERE upper(t.table_name) = upper('customer') ORDER BY c.ordinal_position;
# EOF

#      node_name     |      file_name      |         session_id         |  transaction_id   | statement_id | batch_number | row_number |                                              rejected_data                                              | rejected_data_orig_length |                          rejected_reason
# -------------------+---------------------+----------------------------+-------------------+--------------+--------------+------------+---------------------------------------------------------------------------------------------------------+---------------------------+--------------------------------------------------------------------
#  v_docker_node0001 | STDIN (Batch No. 1) | v_docker_node0001-109:0x17 | 45035996273705370 |           10 |            0 |         12 | ����@_ultralongurlultralongurlultralongurlultralongurlultralongurlultralongurlultralongurultralongurl |                       132 | The 95-byte value is too long for type Varchar(80), column 5 (URL)
# (1 row)




# getting for 3 & 4

#      node_name     |      file_name      |         session_id         |  transaction_id   | statement_id | batch_number | row_number | rejected_data | rejected_data_orig_length |                                    rejected_reason
# -------------------+---------------------+----------------------------+-------------------+--------------+--------------+------------+---------------+---------------------------+----------------------------------------------------------------------------------------
#  v_docker_node0001 | STDIN (Batch No. 1) | v_docker_node0001-109:0x22 | 45035996273705393 |           10 |            0 |          3 | h�P~�Ap��~�A |                        25 | Field size (8) is corrupted for column 7 (MyTimestamp). It does not fit within the row
#  v_docker_node0001 | STDIN (Batch No. 1) | v_docker_node0001-109:0x22 | 45035996273705393 |           10 |            0 |          4 | �`~�A�`~�A |                        25 | Field size (8) is corrupted for column 7 (MyTimestamp). It does not fit within the row
# (2 rows)

exit 0


docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-vertica-sink --describe

docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-vertica-sink --to-earliest --topic customer --reset-offsets --dry-run
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-vertica-sink --to-earliest --topic customer --reset-offsets --execute