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

###
# f1 varchar(2) whereas we set 6 characters string

###
# batch.size = 3000 (default)
###

log "Create the table mytabledefaultbatchsize and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytabledefaultbatchsize(f1 varchar(2));
EOF

sleep 2

log "Sending messages to topic mytabledefaultbatchsize"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytabledefaultbatchsize --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating JDBC Vertica sink connector - default batch.size (3000)"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "topics": "mytabledefaultbatchsize",
                    "errors.tolerance": "all",
                    "errors.log.enable":true,
                    "errors.log.include.messages":true
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytabledefaultbatchsize;
EOF

# [2020-01-16 14:49:15,631] ERROR WorkerSinkTask{id=jdbc-vertica-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: java.sql.BatchUpdateException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.

# 	at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:93)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:539)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:322)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
# 	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
# 	at java.util.concurrent.FutureTask.run(FutureTask.java:266)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)
# Caused by: java.sql.SQLException: java.sql.BatchUpdateException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# java.sql.SQLException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.
# com.vertica.support.exceptions.ErrorException: [Vertica][VJDBC](100172) One or more rows were rejected by the server.

###
# batch.size = 1
###

log "Create the table mytablebatchsizeone and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytablebatchsizeone(f1 varchar(2));
EOF

sleep 2

log "Sending messages to topic mytablebatchsizeone"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytablebatchsizeone --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating JDBC Vertica sink connector - batch.size (1)"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "topics": "mytablebatchsizeone",
                    "batch.size": "1",
                    "errors.tolerance": "all",
                    "errors.log.enable":true,
                    "errors.log.include.messages":true
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytablebatchsizeone;
EOF

# [2020-01-16 14:49:45,207] WARN Write of 10 records failed, remainingRetries=6 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: [Vertica][VJDBC](4800) ERROR: String of 6 octets is too long for type Varchar(2)
# 	at com.vertica.jdbc.common.SStatement.processBatchResults(Unknown Source)
# 	at com.vertica.jdbc.common.SPreparedStatement.executeBatch(Unknown Source)
# 	at com.vertica.jdbc.VerticaJdbc4PreparedStatementImpl.executeBatch(Unknown Source)
# 	at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:211)
# 	at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:177)
# 	at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:159)
# 	at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:66)
# 	at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:74)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:539)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:322)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
# 	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
# 	at java.util.concurrent.FutureTask.run(FutureTask.java:266)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)