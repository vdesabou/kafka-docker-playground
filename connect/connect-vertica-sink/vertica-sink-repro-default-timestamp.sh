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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create the table and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytable(f1 varchar(20),dwhCreationDate timestamp NOT NULL default(sysdate));
EOF


log "Sending messages to topic mytable"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

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
                    "auto.create": "false",
                    "auto.evolve": "false",
                    "topics": "mytable",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytable;
EOF

# [2020-07-30 15:21:23,809] ERROR WorkerSinkTask{id=vertica-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: For input string: ""sysdate"()" (org.apache.kafka.connect.runtime.WorkerSinkTask)
# java.lang.NumberFormatException: For input string: ""sysdate"()"
#         at java.lang.NumberFormatException.forInputString(NumberFormatException.java:65)
#         at java.lang.Integer.parseInt(Integer.java:569)
#         at java.lang.Byte.parseByte(Byte.java:149)
#         at java.lang.Byte.valueOf(Byte.java:205)
#         at java.lang.Byte.valueOf(Byte.java:231)
#         at io.confluent.vertica.VerticaMapperUtil.getDefaultValueOfColumn(VerticaMapperUtil.java:93)
#         at io.confluent.vertica.VerticaDbStructure.getDefaultColumnValue(VerticaDbStructure.java:492)
#         at io.confluent.vertica.VerticaSinkTask.put(VerticaSinkTask.java:156)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:545)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:325)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:228)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:184)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2020-07-30 15:21:23,811] ERROR WorkerSinkTask{id=vertica-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:567)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:325)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:228)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:184)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.lang.NumberFormatException: For input string: ""sysdate"()"
#         at java.lang.NumberFormatException.forInputString(NumberFormatException.java:65)
#         at java.lang.Integer.parseInt(Integer.java:569)
#         at java.lang.Byte.parseByte(Byte.java:149)
#         at java.lang.Byte.valueOf(Byte.java:205)
#         at java.lang.Byte.valueOf(Byte.java:231)
#         at io.confluent.vertica.VerticaMapperUtil.getDefaultValueOfColumn(VerticaMapperUtil.java:93)
#         at io.confluent.vertica.VerticaDbStructure.getDefaultColumnValue(VerticaDbStructure.java:492)
#         at io.confluent.vertica.VerticaSinkTask.put(VerticaSinkTask.java:156)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:545)
#         ... 10 more