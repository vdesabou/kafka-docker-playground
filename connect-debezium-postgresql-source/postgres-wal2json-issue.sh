#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext-wal2json-issue.yml"

#################
# This test is using debezium/postgres:10.0
# which is using Postgres 10 (debezium/postgres:10.0) using wal2json with commit d2b7fef021c46e0d429f2c1768de361069e58696 wal2json 1.0 release 1.0 March 2018
#################
    # using this image we get:
    # 2019-10-29 13:55:20.052 GMT [113] ERROR:  no known snapshots
    # 2019-10-29 13:55:20.052 GMT [113] CONTEXT:  slot "debezium", output plugin "wal2json", in the change callback, associated LSN 0/176B458


# [2019-10-29 13:55:20,056] ERROR Producer failure (io.debezium.pipeline.ErrorHandler)
# org.postgresql.util.PSQLException: ERROR: no known snapshots
#   Where: slot "debezium", output plugin "wal2json", in the change callback, associated LSN 0/176B458
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2497)
#         at org.postgresql.core.v3.QueryExecutorImpl.processCopyResults(QueryExecutorImpl.java:1155)
#         at org.postgresql.core.v3.QueryExecutorImpl.readFromCopy(QueryExecutorImpl.java:1062)
#         at org.postgresql.core.v3.CopyDualImpl.readFromCopy(CopyDualImpl.java:37)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.receiveNextData(V3PGReplicationStream.java:158)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.readInternal(V3PGReplicationStream.java:123)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.readPending(V3PGReplicationStream.java:80)
#         at io.debezium.connector.postgresql.connection.PostgresReplicationConnection$1.readPending(PostgresReplicationConnection.java:401)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.execute(PostgresStreamingChangeEventSource.java:99)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:91)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2019-10-29 13:55:20,058] INFO Creating thread debezium-postgresconnector-asgard-error-handler (io.debezium.util.Threads)
# [2019-10-29 13:55:20,059] ERROR Interrupted while stopping (io.debezium.connector.postgresql.PostgresConnectorTask)
# java.lang.InterruptedException
#         at java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject.awaitNanos(AbstractQueuedSynchronizer.java:2067)
#         at java.util.concurrent.ThreadPoolExecutor.awaitTermination(ThreadPoolExecutor.java:1475)
#         at java.util.concurrent.Executors$DelegatedExecutorService.awaitTermination(Executors.java:675)
#         at io.debezium.pipeline.ErrorHandler.stop(ErrorHandler.java:52)
#         at io.debezium.connector.postgresql.PostgresConnectorTask.cleanupResources(PostgresConnectorTask.java:257)
#         at io.debezium.pipeline.ErrorHandler.lambda$setProducerThrowable$0(ErrorHandler.java:42)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2019-10-29 13:55:20,533] INFO WorkerSourceTask{id=debezium-postgres-source-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2019-10-29 13:55:20,533] INFO WorkerSourceTask{id=debezium-postgres-source-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2019-10-29 13:55:20,534] ERROR WorkerSourceTask{id=debezium-postgres-source-0} Exception thrown while calling task.commit() (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.connect.errors.ConnectException: org.postgresql.util.PSQLException: This replication stream has been closed.
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.commitOffset(PostgresStreamingChangeEventSource.java:178)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.commitOffset(ChangeEventSourceCoordinator.java:109)
#         at io.debezium.connector.postgresql.PostgresConnectorTask.commit(PostgresConnectorTask.java:214)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.commitSourceTask(WorkerSourceTask.java:518)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.commitOffsets(WorkerSourceTask.java:459)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:244)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: org.postgresql.util.PSQLException: This replication stream has been closed.
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.checkClose(V3PGReplicationStream.java:272)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.forceUpdateStatus(V3PGReplicationStream.java:110)
#         at io.debezium.connector.postgresql.connection.PostgresReplicationConnection$1.doFlushLsn(PostgresReplicationConnection.java:434)
#         at io.debezium.connector.postgresql.connection.PostgresReplicationConnection$1.flushLsn(PostgresReplicationConnection.java:427)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.commitOffset(PostgresStreamingChangeEventSource.java:171)
#         ... 12 more
# [2019-10-29 13:55:20,535] ERROR WorkerSourceTask{id=debezium-postgres-source-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: An exception ocurred in the change event producer. This connector will be stopped.
#         at io.debezium.connector.base.ChangeEventQueue.throwProducerFailureIfPresent(ChangeEventQueue.java:170)
#         at io.debezium.connector.base.ChangeEventQueue.poll(ChangeEventQueue.java:151)
#         at io.debezium.connector.postgresql.PostgresConnectorTask.poll(PostgresConnectorTask.java:220)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:259)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: org.postgresql.util.PSQLException: ERROR: no known snapshots
#   Where: slot "debezium", output plugin "wal2json", in the change callback, associated LSN 0/176B458
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2497)
#         at org.postgresql.core.v3.QueryExecutorImpl.processCopyResults(QueryExecutorImpl.java:1155)
#         at org.postgresql.core.v3.QueryExecutorImpl.readFromCopy(QueryExecutorImpl.java:1062)
#         at org.postgresql.core.v3.CopyDualImpl.readFromCopy(CopyDualImpl.java:37)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.receiveNextData(V3PGReplicationStream.java:158)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.readInternal(V3PGReplicationStream.java:123)
#         at org.postgresql.core.v3.replication.V3PGReplicationStream.readPending(V3PGReplicationStream.java:80)
#         at io.debezium.connector.postgresql.connection.PostgresReplicationConnection$1.readPending(PostgresReplicationConnection.java:401)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.execute(PostgresStreamingChangeEventSource.java:99)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:91)
#         ... 5 more

echo "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo "Adding an element to the table"

docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

echo "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo "Creating Debezium PostgreSQL source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "debezium-postgres-source",
               "config": {
                    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "plugin.name": "wal2json",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "postgres",
                    "database.password": "postgres",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.postgres",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw"
          }}' \
     http://localhost:8083/connectors | jq .



sleep 5

echo "Updating elements to the table"

docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc';"
docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc2';"
docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc3';"

echo "Verifying topic asgard.public.customers-raw"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic asgard.public.customers-raw --from-beginning --max-messages 5


