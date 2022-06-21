#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-110472-the-field-configured-for-org.apache.kafka.connect.transforms.extractfield-transform-does-not-exist-in-the-key-or-value-of-kafka-records.yml"


log "Load inventory.sql to SQL Server"
cat ../../connect/connect-debezium-sqlserver-source/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating Debezium SQL Server source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
               "tasks.max": "1",
               "database.hostname": "sqlserver",
               "database.port": "1433",
               "database.user": "sa",
               "database.password": "Password!",
               "database.server.name": "server1",
               "database.dbname" : "testDB",
               "database.history.kafka.bootstrap.servers": "broker:9092",
               "database.history.kafka.topic": "schema-changes.inventory",

               "transforms": "ExtractField",
               "transforms.ExtractField.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
               "transforms.ExtractField.field": "after",

               "_transforms": "after_state_only",
               "transforms.after_state_only.type": "io.debezium.transforms.ExtractNewRecordState"

          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF


# [2022-06-20 09:45:10,904] ERROR [debezium-sqlserver-source|task-0] WorkerSourceTask{id=debezium-sqlserver-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.TransformationChain.transformRecord(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.TransformationChain.apply(TransformationChain.java:50)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:357)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:271)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.IllegalArgumentException: Unknown field: after
#         at org.apache.kafka.connect.transforms.ExtractField.apply(ExtractField.java:65)
#         at org.apache.kafka.connect.runtime.TransformationChain.lambda$transformRecord$0(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 12 more


# {
#     "after": {
#         "server1.dbo.customers.Value": {
#             "email": "ed@walker.com",
#             "first_name": "Edward",
#             "id": 1003,
#             "last_name": "Walker"
#         }
#     },
#     "before": null,
#     "op": "r",
#     "source": {
#         "change_lsn": null,
#         "commit_lsn": {
#             "string": "00000025:000004c0:001a"
#         },
#         "connector": "sqlserver",
#         "db": "testDB",
#         "event_serial_no": null,
#         "name": "server1",
#         "schema": "dbo",
#         "sequence": null,
#         "snapshot": {
#             "string": "true"
#         },
#         "table": "customers",
#         "ts_ms": 1655718360267,
#         "version": "1.9.2.Final"
#     },
#     "transaction": null,
#     "ts_ms": {
#         "long": 1655718360267
#     }
# }

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5
