#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-82340.yml"


log "Describing the outboxevent table in DB 'mydb':"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe outboxevent'"

log "Show content of outboxevent table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from outboxevent'"

# log "Adding an element to the table"
# docker exec mysql mysql --user=root --password=password --database=mydb -e "
# INSERT INTO outboxevent (   \
#   id,   \
#   name, \
#   email,   \
#   last_modified \
# ) VALUES (  \
#   3,    \
#   'another',  \
#   'another@apache.org',   \
#   NOW() \
# ); "

log "Show content of outboxevent table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from outboxevent'"

# https://debezium.io/documentation/reference/1.0/configuration/outbox-event-router.html
log "Creating Debezium MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.mysql.MySqlConnector",
               "tasks.max": "1",
               "database.hostname": "mysql",
               "database.port": "3306",
               "database.user": "debezium",
               "database.password": "dbz",
               "database.server.id": "223344",
               "database.server.name": "dbserver1",
               "database.whitelist": "mydb",
               "database.history.kafka.bootstrap.servers": "broker:9092",
               "database.history.kafka.topic": "schema-changes.mydb",
               "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.schemas.enable": "false",
               "transforms": "RemoveDots,outbox",
               "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
               "transforms.RemoveDots.replacement": "$1_$2_$3",
               "transforms.outbox.type" : "io.debezium.transforms.outbox.EventRouter",
               "transforms.outbox.route.topic.replacement" : "users.events",
               "transforms.outbox.table.fields.additional.placement" : "type:header:eventType"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verify we have received the protobuf data in dbserver1_mydb_outboxevent topic"
timeout 60 docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_outboxevent --from-beginning --max-messages 2

# [2021-12-16 09:11:40,238] ERROR [debezium-mysql-source|task-0] WorkerSourceTask{id=debezium-mysql-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.convertTransformedRecord(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:359)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:272)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.IllegalArgumentException: Unsupported root schema of type BYTES
#         at io.confluent.connect.protobuf.ProtobufData.rawSchemaFromConnectSchema(ProtobufData.java:627)
#         at io.confluent.connect.protobuf.ProtobufData.fromConnectSchema(ProtobufData.java:615)
#         at io.confluent.connect.protobuf.ProtobufData.fromConnectData(ProtobufData.java:321)
#         at io.confluent.connect.protobuf.ProtobufConverter.fromConnectData(ProtobufConverter.java:85)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$4(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 11 more