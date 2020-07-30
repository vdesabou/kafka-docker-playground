#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-10.0.0-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/10.0.x/10.0.0-0/vertica-client-10.0.0-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-10.0.0-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-10.0.0-0.x86_64.tar.gz
fi

if [ ! -f ${DIR}/EmptySchema/target/EmptySchema-1.0.0-SNAPSHOT.jar ]
then
     # build EmptySchema transform
     log "Build EmptySchema transform"
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/EmptySchema":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/EmptySchema/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

if [ ! -f ${DIR}/producer/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer"
     docker run -it --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi



${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-dv.yml"

docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
CREATE TABLE public.customer1
(
    ListID int,
    NormalizedHashItemID int,
    KafkaKeyIsDeleted boolean DEFAULT true,
    MyFloatValue float,
    is_deleted boolean NOT NULL default(true),
    dwhCreationDate timestamp NOT NULL default(sysdate)
);
EOF

# docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
# DROP TABLE public.customer1;
# EOF

log "Sending messages to topic customer (done using JAVA producer)"

sleep 6

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
                    "config.action.reload": "restart",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true",
                    "topics": "customer",
                    "rejected.record.logging.mode": "log",
                    "table.name.format": "public.customer1",
                    "auto.create": "true",
                    "auto.evolve": "false",
                    "key.converter": "org.apache.kafka.connect.converters.LongConverter",
                    "value.converter" : "Avro",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .


sleep 30

log "Check data is in Vertica for customer1"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from public.customer1;
EOF

# [2020-07-30 14:51:34,012] ERROR WorkerSinkTask{id=vertica-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: For input string: "(statement_timestamp())::timestamp" (org.apache.kafka.connect.runtime.WorkerSinkTask)
# java.lang.NumberFormatException: For input string: "(statement_timestamp())::timestamp"
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