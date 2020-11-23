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

if [ ! -f ${DIR}/producer-repro-null/target/producer-repro-null-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer-repro-null"
     docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer-repro-null":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer-repro-null/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

if [ ! -f ${DIR}/vertica-stream-writer/target/vertica-stream-writer-0.0.1-SNAPSHOT.jar ]
then
     log "Build vertica-stream-writer-0.0.1-SNAPSHOT.jar"
     git clone https://github.com/jcustenborder/vertica-stream-writer.git
     cp ${DIR}/QueryBuilder.java vertica-stream-writer/src/main/java/com/github/jcustenborder/vertica/QueryBuilder.java
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/vertica-stream-writer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/vertica-stream-writer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-null.yml"


log "Create the table customer"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE TABLE public.customer
(
    f1 int,
    f2 int,
    f3 int
);
EOF

sleep 2

log "Sending messages to topic customer (done using JAVA producer)"

log "Creating Vertica sink connector"
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
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "vertica.load.method": "DIRECT",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica for customer"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer;
EOF

# FIXTHIS: getting error:

# [2020-02-19 10:15:50,265] INFO put() - Imported 3 record(s) in 147 millisecond(s). (io.confluent.vertica.VerticaSinkTask)
# [2020-02-19 10:15:50,319] ERROR WorkerSinkTask{id=vertica-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: [Vertica][VJDBC](3591) INTERNAL: Internal EE Error (11)
#   [Vertica][VJDBC]Detail: blockOffset + sz <= (ssize_t)blockLength
#         at io.confluent.vertica.VerticaSinkTask.put(VerticaSinkTask.java:240)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:539)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:322)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.sql.SQLException: [Vertica][VJDBC](3591) INTERNAL: Internal EE Error (11)
#   [Vertica][VJDBC]Detail: blockOffset + sz <= (ssize_t)blockLength
#         at com.vertica.util.ServerErrorData.buildException(Unknown Source)
#         at com.vertica.dataengine.VResultSet.fetchChunk(Unknown Source)
#         at com.vertica.dataengine.VResultSet.initialize(Unknown Source)
#         at com.vertica.dataengine.VQueryExecutor.endCopy(Unknown Source)
#         at com.vertica.core.VConnection.endCurrentCopy(Unknown Source)
#         at com.vertica.dataengine.VDataEngine.prepareImpl(Unknown Source)
#         at com.vertica.dataengine.VDataEngine.prepare(Unknown Source)
#         at com.vertica.dataengine.SimpleQueryExecutor.execute(Unknown Source)
#         at com.vertica.dataengine.SimpleQueryExecutor.execute(Unknown Source)
#         at com.vertica.core.VConnection.executeTransactionStatement(Unknown Source)
#         at com.vertica.core.VConnection.commit(Unknown Source)
#         at com.vertica.jdbc.common.SConnection.commit(Unknown Source)
#         at com.vertica.jdbc.VerticaJdbc4ConnectionImpl.commit(Unknown Source)
#         at com.zaxxer.hikari.pool.ProxyConnection.commit(ProxyConnection.java:353)
#         at com.zaxxer.hikari.pool.HikariProxyConnection.commit(HikariProxyConnection.java)
#         at io.confluent.vertica.VerticaSinkTask.put(VerticaSinkTask.java:238)
#         ... 11 more
# Caused by: com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](3591) INTERNAL: Internal EE Error (11)
#   [Vertica][VJDBC]Detail: blockOffset + sz <= (ssize_t)blockLength
#         ... 27 more


# With int, getting:

# [2020-02-19 10:23:35,596] WARN put() - Rejected 3 record(s). (io.confluent.vertica.VerticaSinkTask)
# [2020-02-19 10:23:35,596] WARN Rejected row 1 (io.confluent.vertica.VerticaSinkTask)
# [2020-02-19 10:23:35,596] WARN Rejected row 2 (io.confluent.vertica.VerticaSinkTask)
# [2020-02-19 10:23:35,596] WARN Rejected row 3 (io.confluent.vertica.VerticaSinkTask)

log "Check for rejected data for customer1"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer_rej;
EOF

#      node_name     |      file_name      |         session_id         |  transaction_id   | statement_id | batch_number | row_number | rejected_data | rejected_data_orig_length |                                rejected_reason
# -------------------+---------------------+----------------------------+-------------------+--------------+--------------+------------+---------------+---------------------------+-------------------------------------------------------------------------------
#  v_docker_node0001 | STDIN (Batch No. 1) | v_docker_node0001-109:0x20 | 45035996273705275 |           10 |            0 |          1 |             |                        16 | Field size (8) is corrupted for column 3 (f3). It does not fit within the row