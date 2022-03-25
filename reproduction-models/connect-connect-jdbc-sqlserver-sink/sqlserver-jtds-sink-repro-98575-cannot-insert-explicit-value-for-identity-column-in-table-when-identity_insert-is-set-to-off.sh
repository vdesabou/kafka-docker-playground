#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-98575-cannot-insert-explicit-value-for-identity-column-in-table-when-identity_insert-is-set-to-off.yml"

log "Load inventory-repro-98575.sql to SQL Server"
cat inventory-repro-98575.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

# it doesn't not work see https://stackoverflow.com/a/43556579/2381999
# docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! <<-EOF
# use testDB;
# SET IDENTITY_INSERT customers ON;
# GO
# EOF

log "Creating JDBC SQL Server (with JTDS driver) sink connector"
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
               "auto.evolve": "true",
               "insert.mode": "upsert", 
               "pk.mode": "record_key", 
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.retry.delay.max.ms": "60000",
               "errors.retry.timeout": "0",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Sending messages to topic customers"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"first_name", "type": "string"}]}' --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"first_name": "vincent"}
EOF

sleep 5

log "Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
use testDB;
select * from customers
GO
EOF
cat /tmp/result.log
grep "vincent" /tmp/result.log

# 11:33:43 ℹ️ Show content of customers table:
# Changed database context to 'testDB'.
# id          first_name          
# ----------- --------------------
#           1 Sally               
#           2 George              
#           3 Edward              
#           4 Anne   


# [2022-03-25 11:33:54,993] ERROR [sqlserver-sink|task-0] WorkerSinkTask{id=sqlserver-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask:627)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Cannot insert explicit value for identity column in table 'customers' when IDENTITY_INSERT is set to OFF.

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Cannot insert explicit value for identity column in table 'customers' when IDENTITY_INSERT is set to OFF.

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2022-03-25 11:33:57,994] INFO [sqlserver-sink|task-0] Attempting to open connection #1 to SqlServer (io.confluent.connect.jdbc.util.CachedConnectionProvider:79)
# [2022-03-25 11:33:58,013] INFO [sqlserver-sink|task-0] JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter:56)
# [2022-03-25 11:33:58,029] INFO [sqlserver-sink|task-0] Checking SqlServer dialect for existence of TABLE "dbo"."customers" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:583)
# [2022-03-25 11:33:58,031] INFO [sqlserver-sink|task-0] Using SqlServer dialect TABLE "dbo"."customers" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:591)
# [2022-03-25 11:33:58,052] INFO [sqlserver-sink|task-0] Checking SqlServer dialect for type of TABLE "dbo"."customers" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:853)
# [2022-03-25 11:33:58,054] INFO [sqlserver-sink|task-0] Setting metadata for table "dbo"."customers" to Table{name='"dbo"."customers"', type=TABLE columns=[Column{'first_name', isPrimaryKey=false, allowsNull=false, sqlType=varchar}, Column{'id', isPrimaryKey=true, allowsNull=false, sqlType=int identity}]} (io.confluent.connect.jdbc.util.TableDefinitions:64)
# [2022-03-25 11:33:58,056] WARN [sqlserver-sink|task-0] Write of 1 records failed, remainingRetries=4 (io.confluent.connect.jdbc.sink.JdbcSinkTask:92)
# java.sql.BatchUpdateException: Cannot insert explicit value for identity column in table 'customers' when IDENTITY_INSERT is set to OFF.
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.executeBatch(SQLServerPreparedStatement.java:2088)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)