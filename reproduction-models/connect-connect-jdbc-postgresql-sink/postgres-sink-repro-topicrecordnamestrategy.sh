#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=postgres&password=postgres&ssl=false",
               "topics": "topicrecordnamestrategy",
               "auto.create": "true",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.value.subject.name.strategy": "io.confluent.kafka.serializers.subject.TopicRecordNameStrategy"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .

sleep 5

seq -f "{\"foo\": %g,\"bar\": \"a string\",\"onemore\": \"onemore string\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic topicrecordnamestrategy --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"foo","type":"int"},{"name":"bar","type":"string"},{"name":"onemore","type":"string", "default": "green"}]}' --property value.subject.name.strategy=io.confluent.kafka.serializers.subject.TopicRecordNameStrategy

seq -f "{\"foo\": %g,\"bar\": \"a string\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic topicrecordnamestrategy --property value.schema='{"type":"record","name":"myrecord2","fields":[{"name":"foo","type":"int"},{"name":"bar","type":"string"}]}' --property value.subject.name.strategy=io.confluent.kafka.serializers.subject.TopicRecordNameStrategy

log "Show content of TOPICRECORDNAMESTRATEGY table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM TOPICRECORDNAMESTRATEGY'"

# if messages are not FORARD or BACKWARD compatible
# [2021-03-01 17:36:40,731] ERROR WorkerSinkTask{id=postgres-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Cannot ALTER TABLE "topicrecordnamestrategy" to add missing field SinkRecordField{schema=Schema{STRING}, name='name', isPrimaryKey=false}, as the field is not optional and does not have a default value (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.ConnectException: Cannot ALTER TABLE "topicrecordnamestrategy" to add missing field SinkRecordField{schema=Schema{STRING}, name='name', isPrimaryKey=false}, as the field is not optional and does not have a default value
#         at io.confluent.connect.jdbc.sink.DbStructure.amendIfNecessary(DbStructure.java:180)
#         at io.confluent.connect.jdbc.sink.DbStructure.createOrAmendIfNecessary(DbStructure.java:81)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:123)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:73)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:75)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:586)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)