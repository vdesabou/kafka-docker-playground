#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/sqljdbc_7.4/enu/mssql-jdbc-7.4.1.jre8.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-7.4.1.jre8.jar"
     wget https://download.microsoft.com/download/6/9/9/699205CA-F1F1-4DE9-9335-18546C5C8CBD/sqljdbc_7.4.1.0_enu.tar.gz
     tar xvfz sqljdbc_7.4.1.0_enu.tar.gz
     rm -f sqljdbc_7.4.1.0_enu.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft.repro-110836-binary-handling-with-null-value.yml"

log "Load inventory-repro-110836.sql to SQL Server"
cat inventory-repro-110836.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.jdbc \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "customers",
               "auto.create": "false",
               "auto.evolve": "false",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.object.additional.properties" : "false",

               "delete.enabled" : "true",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name":"dlq",
               "errors.deadletterqueue.topic.replication.factor": 1,
               "errors.deadletterqueue.context.headers.enable":true,
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "insert.mode": "upsert",
               "_time.precision.mode": "connect",
               "pk.mode": "record_key",
               "pk.fields": "f0"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .


log "send messages to customers"
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property key.schema='{"type":"object","properties":{"f0":{"type":"string"}}}' --property value.schema='{"type":"object","properties":{"f1":{"type":"string"},"f2":{"oneOf": [ {"type": "null"},{"connect.type": "bytes","type": "string"}]}}}'  --property parse.key=true --property key.separator="|" << EOF
{"f0": "1"}|{"f1": "1","f2":"ZG1Gc2RXVXg="}
{"f0": "2"}|{"f1": "2","f2":null}
EOF


# [2022-06-27 09:30:39,660] DEBUG [sqlserver-sink|task-0] UPSERT sql: merge into "dbo"."customers" with (HOLDLOCK) AS target using (select ? AS "f0", ? AS "f1", ? AS "f2") AS incoming on (target."f0"=incoming."f0") when matched then update set "f1"=incoming."f1","f2"=incoming."f2" when not matched then insert ("f1", "f2", "f0") values (incoming."f1",incoming."f2",incoming."f0"); deleteSql: DELETE FROM "dbo"."customers" WHERE "f0" = ? meta: FieldsMetadata{keyFieldNames=[f0], nonKeyFieldNames=[f1, f2], allFields={f1=SinkRecordField{schema=Schema{STRING}, name='f1', isPrimaryKey=false}, f2=SinkRecordField{schema=Schema{BYTES}, name='f2', isPrimaryKey=false}, f0=SinkRecordField{schema=Schema{STRING}, name='f0', isPrimaryKey=true}}} (io.confluent.connect.jdbc.sink.BufferedRecords:130)
# [2022-06-27 09:30:39,660] DEBUG [sqlserver-sink|task-0] Closing BufferedRecords with updatePreparedStatement: null deletePreparedStatement: null (io.confluent.connect.jdbc.sink.BufferedRecords:218)
# [2022-06-27 09:30:39,660] TRACE [sqlserver-sink|task-0] Creating a PreparedStatement 'merge into "dbo"."customers" with (HOLDLOCK) AS target using (select ? AS "f0", ? AS "f1", ? AS "f2") AS incoming on (target."f0"=incoming."f0") when matched then update set "f1"=incoming."f1","f2"=incoming."f2" when not matched then insert ("f1", "f2", "f0") values (incoming."f1",incoming."f2",incoming."f0");' (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:367)
# [2022-06-27 09:30:39,661] TRACE [sqlserver-sink|task-0] Creating a PreparedStatement 'DELETE FROM "dbo"."customers" WHERE "f0" = ?' (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:367)
# [2022-06-27 09:30:39,662] DEBUG [sqlserver-sink|task-0] Flushing records in JDBC Writer for table ID: "dbo"."customers" (io.confluent.connect.jdbc.sink.JdbcDbWriter:79)
# [2022-06-27 09:30:39,662] DEBUG [sqlserver-sink|task-0] Flushing 2 buffered records (io.confluent.connect.jdbc.sink.BufferedRecords:178)
# [2022-06-27 09:30:39,675] DEBUG [sqlserver-sink|task-0] Closing BufferedRecords with updatePreparedStatement: SQLServerPreparedStatement:7 deletePreparedStatement: SQLServerPreparedStatement:8 (io.confluent.connect.jdbc.sink.BufferedRecords:218)

#  Creating table with sql: CREATE TABLE "dbo"."customers" (
# "f1" varchar(max) NOT NULL,
# "f2" varbinary(max) NULL)

sleep 5

log "Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
use testDB
select * from customers
GO
EOF
cat /tmp/result.log

sleep 10

log "send message with null for binary field"
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property key.schema='{"type":"object","properties":{"f0":{"type":"string"}}}' --property value.schema='{"type":"object","properties":{"f1":{"type":"string"},"f2":{"oneOf": [ {"type": "null"},{"connect.type": "bytes","type": "string"}]}}}'  --property parse.key=true --property key.separator="|" << EOF
{"f0": "4"}|{"f1": "3","f2":null}
EOF
# if more than one record, example if I add {"f0": "4"}|{"f1": "4","f2":"ZG1Gc2RXVXg="} then it does not fail !

sleep 10

log "Check DLQ"
set +e
timeout 30 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic dlq --from-beginning --property print.headers=true
set -e


# [2022-06-27 09:31:27,609] DEBUG [sqlserver-sink|task-0] UPSERT sql: merge into "dbo"."customers" with (HOLDLOCK) AS target using (select ? AS "f0", ? AS "f1", ? AS "f2") AS incoming on (target."f0"=incoming."f0") when matched then update set "f1"=incoming."f1","f2"=incoming."f2" when not matched then insert ("f1", "f2", "f0") values (incoming."f1",incoming."f2",incoming."f0"); deleteSql: DELETE FROM "dbo"."customers" WHERE "f0" = ? meta: FieldsMetadata{keyFieldNames=[f0], nonKeyFieldNames=[f1, f2], allFields={f1=SinkRecordField{schema=Schema{STRING}, name='f1', isPrimaryKey=false}, f2=SinkRecordField{schema=Schema{BYTES}, name='f2', isPrimaryKey=false}, f0=SinkRecordField{schema=Schema{STRING}, name='f0', isPrimaryKey=true}}} (io.confluent.connect.jdbc.sink.BufferedRecords:130)
# [2022-06-27 09:31:27,609] DEBUG [sqlserver-sink|task-0] Closing BufferedRecords with updatePreparedStatement: null deletePreparedStatement: null (io.confluent.connect.jdbc.sink.BufferedRecords:218)
# [2022-06-27 09:31:27,609] TRACE [sqlserver-sink|task-0] Creating a PreparedStatement 'merge into "dbo"."customers" with (HOLDLOCK) AS target using (select ? AS "f0", ? AS "f1", ? AS "f2") AS incoming on (target."f0"=incoming."f0") when matched then update set "f1"=incoming."f1","f2"=incoming."f2" when not matched then insert ("f1", "f2", "f0") values (incoming."f1",incoming."f2",incoming."f0");' (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:367)
# [2022-06-27 09:31:27,609] TRACE [sqlserver-sink|task-0] Creating a PreparedStatement 'DELETE FROM "dbo"."customers" WHERE "f0" = ?' (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:367)

# __connect.errors.topic:customers,__connect.errors.partition:0,__connect.errors.offset:6,__connect.errors.connector.name:sqlserver-sink,__connect.errors.task.id:0,__connect.errors.stage:TASK_PUT,__connect.errors.class.name:org.apache.kafka.connect.sink.SinkTask,__connect.errors.exception.class.name:java.sql.SQLException,__connect.errors.exception.message:Exception chain:
# java.sql.BatchUpdateException: Implicit conversion from data type nvarchar to binary is not allowed. Use the CONVERT function to run this query.
# ,__connect.errors.exception.stacktrace:java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Implicit conversion from data type nvarchar to binary is not allowed. Use the CONVERT function to run this query.

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.unrollAndRetry(JdbcSinkTask.java:138)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:111)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
#         {"f1":"2","f2":null}



# [2022-06-24 21:29:33,376] ERROR [sqlserver-sink|task-0] WorkerSinkTask{id=sqlserver-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask:607)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Implicit conversion from data type nvarchar to binary is not allowed. Use the CONVERT function to run this query.

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Implicit conversion from data type nvarchar to binary is not allowed. Use the CONVERT function to run this query.

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more


log "Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
use testDB
select * from customers
GO
EOF
cat /tmp/result.log