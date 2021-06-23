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
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "orders",
               "auto.create": "true",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.log.enable": "true",
               "errors.log.include.messages": "false",
               "errors.retry.delay.max.ms": "60000",
               "errors.retry.timeout": "0",
               "errors.tolerance" :"all"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"fields":[{"type":"int","name":"id"},{"type":"string","name":"product"},{"type":"int","name":"quantity"},{"type":"float","name":"price"},{"type":{"logicalType": "timestamp-millis","type": "long"},"name":"tsm"}],"type":"record","name":"myrecord"}' << EOF
{"id": 1000, "product": "foo", "quantity": 100, "price": 50, "tsm": 162444549568588899}
EOF

log "let some time for all the retries to fail..."
sleep 120


log "Show content of ORDERS table: it fails with ERROR:  relation orders does not exist"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERS'"

# [2021-06-23 11:13:23,956] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:24,045] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:24,067] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:24,073] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:24,075] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:24,080] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:24,082] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:24,099] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:24,102] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:24,123] WARN Write of 1 records failed, remainingRetries=10 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:24,125] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:24,126] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:24,126] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:27,130] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:27,155] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:27,168] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:27,182] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:27,182] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:27,198] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:27,205] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:27,218] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:27,221] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:27,225] WARN Write of 1 records failed, remainingRetries=9 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:27,228] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:27,228] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:27,228] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:30,230] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:30,234] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:30,240] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:30,246] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:30,246] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:30,250] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:30,252] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:30,259] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:30,260] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:30,263] WARN Write of 1 records failed, remainingRetries=8 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:30,264] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:30,264] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:30,264] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:33,265] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:33,269] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:33,274] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:33,280] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:33,280] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:33,284] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:33,286] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:33,297] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:33,299] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:33,301] WARN Write of 1 records failed, remainingRetries=7 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:33,302] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:33,302] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:33,302] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:36,304] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:36,308] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:36,313] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:36,316] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:36,316] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:36,321] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:36,322] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:36,330] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:36,332] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:36,333] WARN Write of 1 records failed, remainingRetries=6 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:36,334] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:36,334] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:36,334] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:39,336] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:39,341] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:39,347] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:39,350] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:39,350] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:39,357] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:39,360] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:39,371] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:39,376] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:39,378] WARN Write of 1 records failed, remainingRetries=5 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:39,378] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:39,379] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:39,379] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:42,381] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:42,386] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:42,391] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:42,395] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:42,396] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:42,402] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:42,404] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:42,415] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:42,420] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:42,423] WARN Write of 1 records failed, remainingRetries=4 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:42,423] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:42,424] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:42,424] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:45,426] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:45,430] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:45,434] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:45,437] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:45,438] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:45,443] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:45,445] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:45,451] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:45,453] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:45,454] WARN Write of 1 records failed, remainingRetries=3 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:45,455] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:45,455] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:45,455] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:48,457] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:48,464] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:48,470] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:48,473] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:48,473] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:48,477] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:48,479] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:48,486] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:48,488] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:48,494] WARN Write of 1 records failed, remainingRetries=2 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:48,496] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:48,498] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:48,499] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:51,499] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:51,504] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:51,509] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:51,511] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:51,512] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:51,516] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:51,518] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:51,523] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:51,525] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:51,527] WARN Write of 1 records failed, remainingRetries=1 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:51,527] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:51,527] INFO Initializing writer using SQL dialect: PostgreSqlDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# [2021-06-23 11:13:51,528] ERROR WorkerSinkTask{id=postgres-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
# org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
#         ... 11 more
# [2021-06-23 11:13:54,529] INFO Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:54,534] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:54,539] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:54,542] INFO Using PostgreSql dialect TABLE "orders" absent (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:54,542] INFO Creating table with sql: CREATE TABLE "orders" (
# "id" INT NOT NULL,
# "product" TEXT NOT NULL,
# "quantity" INT NOT NULL,
# "price" REAL NOT NULL,
# "tsm" TIMESTAMP NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure)
# [2021-06-23 11:13:54,549] INFO Checking PostgreSql dialect for existence of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:54,551] INFO Using PostgreSql dialect TABLE "orders" present (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:54,560] INFO Checking PostgreSql dialect for type of TABLE "orders" (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect)
# [2021-06-23 11:13:54,561] INFO Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'tsm', isPrimaryKey=false, allowsNull=false, sqlType=timestamp}, Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'product', isPrimaryKey=false, allowsNull=false, sqlType=text}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions)
# [2021-06-23 11:13:54,562] WARN Write of 1 records failed, remainingRetries=0 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"  Call getNextException to see other errors in the batch.
#         at org.postgresql.jdbc.BatchResultHandler.handleError(BatchResultHandler.java:169)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2286)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:521)
#         at org.postgresql.jdbc.PgStatement.internalExecuteBatch(PgStatement.java:878)
#         at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:901)
#         at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1644)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.postgresql.util.PSQLException: ERROR: timestamp out of range: "5149632-11-07 15:16:28.899+00"
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2553)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2285)
#         ... 19 more
# [2021-06-23 11:13:54,563] INFO Closing connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:54,563] INFO Attempting to open connection #2 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:54,571] INFO JdbcDbWriter Connected (io.confluent.connect.jdbc.sink.JdbcDbWriter)
# [2021-06-23 11:13:54,574] ERROR Error encountered in task postgres-sink-0. Executing stage 'TASK_PUT' with class 'org.apache.kafka.connect.sink.SinkTask'. (org.apache.kafka.connect.runtime.errors.LogReporter)
# java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","product","quantity","price","tsm") VALUES (1000,'foo',100,50.0,'5149632-11-07 15:16:28.899+00') was aborted: ERROR: relation "orders" does not exist
#   Position: 13  Call getNextException to see other errors in the batch.
# org.postgresql.util.PSQLException: ERROR: relation "orders" does not exist
#   Position: 13
# org.postgresql.util.PSQLException: ERROR: relation "orders" does not exist
#   Position: 13

#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.unrollAndRetry(JdbcSinkTask.java:138)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:111)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2021-06-23 11:13:54,593] INFO Closing connection #2 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
# [2021-06-23 11:13:54,597] INFO creating interceptor (io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor)
# [2021-06-23 11:13:54,598] INFO MonitoringInterceptorConfig values:
#         confluent.monitoring.interceptor.publishMs = 15000
#         confluent.monitoring.interceptor.topic = _confluent-monitoring
#  (io.confluent.monitoring.clients.interceptor.MonitoringInterceptorConfig)
# [2021-06-23 11:13:54,599] INFO ProducerConfig values:
#         acks = -1
#         batch.size = 16384
#         bootstrap.servers = [broker:9092]
#         buffer.memory = 33554432
#         client.dns.lookup = use_all_dns_ips
#         client.id = confluent.monitoring.interceptor.connect-worker-producer
#         compression.type = lz4
#         connections.max.idle.ms = 540000
#         delivery.timeout.ms = 120000
#         enable.idempotence = false
#         interceptor.classes = []
#         internal.auto.downgrade.txn.commit = false
#         key.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#         linger.ms = 500
#         max.block.ms = 60000
#         max.in.flight.requests.per.connection = 1
#         max.request.size = 10485760
#         metadata.max.age.ms = 300000
#         metadata.max.idle.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
#         receive.buffer.bytes = 32768
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 500
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 30000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         transaction.timeout.ms = 60000
#         transactional.id = null
#         value.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#  (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-06-23 11:13:54,602] INFO Kafka version: 6.2.0-ce (org.apache.kafka.common.utils.AppInfoParser)
# [2021-06-23 11:13:54,602] INFO Kafka commitId: 5c753752ae1445a1 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-06-23 11:13:54,602] INFO Kafka startTimeMs: 1624446834602 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-06-23 11:13:54,602] INFO interceptor=confluent.monitoring.interceptor.connect-worker-producer created for client_id=connect-worker-producer client_type=PRODUCER session= cluster=XzwWRxsKSDGjcgZkHMSCig (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor)
# [2021-06-23 11:13:54,607] INFO [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer] Cluster ID: XzwWRxsKSDGjcgZkHMSCig (org.apache.kafka.clients.Metadata)