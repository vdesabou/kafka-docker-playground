#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-106956-issue-with-pk-mode.yml"

log "Creating MySQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "topics": "customer_json3",
                    "auto.create": "true",
                    "delete.enabled": "false",
                    "insert.mode": "upsert",

                    "pk.mode": "record_value",
                    "pk.fields": "id",

                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "key.converter.schemas.enable": "false",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/mysql-sink/config | jq .



log "Sending messages to topic customer_json3"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic customer_json3 --property parse.key=true --property key.separator=, << EOF
,{"id": 1, "product": "foo", "quantity": 100, "price": 50}
{"mykey": "key2"},{"id": 2, "product": "foo", "quantity": 100, "price": 50}
{"mykey": "key3"},{"id": 3, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5


# [2022-06-09 08:28:40,488] ERROR [mysql-sink|task-0] WorkerSinkTask{id=mysql-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Sink connector 'mysql-sink' is configured with 'delete.enabled=false' and 'pk.mode=record_value' and therefore requires records with a non-null Struct value and non-null Struct schema, but found record at (topic='customer_json3',partition=0,offset=0,timestamp=1654763308503) with a HashMap value and null value schema. (org.apache.kafka.connect.runtime.WorkerSinkTask:616)
# org.apache.kafka.connect.errors.ConnectException: Sink connector 'mysql-sink' is configured with 'delete.enabled=false' and 'pk.mode=record_value' and therefore requires records with a non-null Struct value and non-null Struct schema, but found record at (topic='customer_json3',partition=0,offset=0,timestamp=1654763308503) with a HashMap value and null value schema.
#         at io.confluent.connect.jdbc.sink.RecordValidator.lambda$requiresValue$2(RecordValidator.java:86)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:81)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# [2022-06-09 08:28:40,489] ERROR [mysql-sink|task-0] WorkerSinkTask{id=mysql-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Sink connector 'mysql-sink' is configured with 'delete.enabled=false' and 'pk.mode=record_value' and therefore requires records with a non-null Struct value and non-null Struct schema, but found record at (topic='customer_json3',partition=0,offset=0,timestamp=1654763308503) with a HashMap value and null value schema.
#         at io.confluent.connect.jdbc.sink.RecordValidator.lambda$requiresValue$2(RecordValidator.java:86)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:81)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more


# Data mapping
# The sink connector requires knowledge of schemas, so you should use a suitable converter. For example, the Avro converter that comes with Schema Registry, the JSON converter with schemas enabled, or the Protobuf converter. Kafka record keys, if present, can be primitive types or a Connect struct, and the record value must be a Connect struct. Fields being selected from Connect structs must be of primitive types. If the data in the topic is not of a compatible format, implementing a custom Converter may be necessary.

log "Describing the customer_json3 table in DB 'db':"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe customer_json3'"

log "Show content of customer_json3 table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from customer_json3'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log


