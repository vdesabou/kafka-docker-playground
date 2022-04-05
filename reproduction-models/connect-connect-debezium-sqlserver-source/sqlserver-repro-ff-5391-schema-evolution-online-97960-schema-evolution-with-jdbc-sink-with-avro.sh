#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-ff-5391-schema-evolution-online-97960-schema-evolution-with-jdbc-sink.yml"


log "Load ./repro-ff-5391/inventory.sql to SQL Server"
cat ./repro-ff-5391/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

# log "workaround: set compatibility to NONE"
# curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data '{"compatibility": "NONE"}' http://localhost:8081/config/server1.dbo.customers-value

log "Creating Debezium SQL Server source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
               "tasks.max": "1",
               "database.hostname": "sqlserver",
               "database.port": "1433",
               "database.user": "vincent",
               "database.password": "Password!",
               "database.server.name": "server1",
               "database.dbname" : "testDB",
               "database.history.kafka.bootstrap.servers": "broker:9092",
               "database.history.kafka.topic": "schema-changes.inventory",

               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",

               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",

               "transforms": "after_state_only",
               "transforms.after_state_only.type": "io.debezium.transforms.ExtractNewRecordState"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

log "Connector status: it is running"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .

log "Make an insert"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam@office.com');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5

log "Creating JDBC SQL Server (with JTDS driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "server1.dbo.customers",
               "auto.create": "true",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.object.additional.properties" : "false",
               "auto.create": "true",
               "auto.evolve": "false",
               "pk.mode": "record_key",
               "insert.mode": "upsert",
               "delete.enabled" : "true",
               "auto.offset.reset": "latest",
               "table.name.format": "customers",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.retry.delay.max.ms": "6000",
               "errors.retry.timeout": "0",
               "errors.tolerance": "all",
               "time.precision.mode": "connect"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

sleep 10

log "JDBC SINK: Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;
select * from master.dbo.customers
GO
EOF
cat /tmp/result.log

# log "Change compatibility mode to NONE"
# curl --request PUT \
#   --url http://localhost:8081/config \
#   --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
#   --data '{
#     "compatibility": "NONE"
# }'
log "alter manually destination table to add column ( "auto.evolve": "false")"
cat ./repro-97960/alter-dest-table-add-column.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


# [{"topic":"dlq","partition":0,"offset":0,"timestamp":1649156641519,"timestampType":"CREATE_TIME","headers":[{"key":"__connect.errors.topic","stringValue":"server1.dbo.customers"},{"key":"__connect.errors.partition","stringValue":"0"},{"key":"__connect.errors.offset","stringValue":"5"},{"key":"__connect.errors.connector.name","stringValue":"sqlserver-sink"},{"key":"__connect.errors.task.id","stringValue":"0"},{"key":"__connect.errors.stage","stringValue":"TASK_PUT"},{"key":"__connect.errors.class.name","stringValue":"org.apache.kafka.connect.sink.SinkTask"},{"key":"__connect.errors.exception.class.name","stringValue":"io.confluent.connect.jdbc.sink.TableAlterOrCreateException"},{"key":"__connect.errors.exception.message","stringValue":"Table \"dbo\".\"customers\" is missing fields ([SinkRecordField{schema=Schema{STRING}, name='phone_number', isPrimaryKey=false}]) and auto-evolution is disabled"},{"key":"__connect.errors.exception.stacktrace","stringValue":"io.confluent.connect.jdbc.sink.TableAlterOrCreateException: Table \"dbo\".\"customers\" is missing fields ([SinkRecordField{schema=Schema{STRING}, name='phone_number', isPrimaryKey=false}]) and auto-evolution is disabled\n\tat io.confluent.connect.jdbc.sink.DbStructure.amendIfNecessary(DbStructure.java:193)\n\tat io.confluent.connect.jdbc.sink.DbStructure.createOrAmendIfNecessary(DbStructure.java:83)\n\tat io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:123)\n\tat io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)\n\tat io.confluent.connect.jdbc.sink.JdbcSinkTask.unrollAndRetry(JdbcSinkTask.java:133)\n\tat io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:87)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\n"}],"key":{"id":1006},"value":{"id":1006,"first_name":"John","last_name":"Doe","email":"john.doe@example.com","phone_number":{"string":"+1-555-123456"}},"__confluent_index":0}]


# __connect.errors.topic:server1.dbo.customers,__connect.errors.partition:0,__connect.errors.offset:5,__connect.errors.connector.name:sqlserver-sink,__connect.errors.task.id:0,__connect.errors.stage:TASK_PUT,__connect.errors.class.name:org.apache.kafka.connect.sink.SinkTask,__connect.errors.exception.class.name:io.confluent.connect.jdbc.sink.TableAlterOrCreateException,__connect.errors.exception.message:Table "dbo"."customers" is missing fields ([SinkRecordField{schema=Schema{STRING}, name='phone_number', isPrimaryKey=false}]) and auto-evolution is disabled,__connect.errors.exception.stacktrace:io.confluent.connect.jdbc.sink.TableAlterOrCreateException: Table "dbo"."customers" is missing fields ([SinkRecordField{schema=Schema{STRING}, name='phone_number', isPrimaryKey=false}]) and auto-evolution is disabled
#         at io.confluent.connect.jdbc.sink.DbStructure.amendIfNecessary(DbStructure.java:193)
#         at io.confluent.connect.jdbc.sink.DbStructure.createOrAmendIfNecessary(DbStructure.java:83)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:123)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.unrollAndRetry(JdbcSinkTask.java:133)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:87)
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
#         JohnDoe(john.doe@example.com+1-555-123456
# __connect.errors.topic:server1.dbo.customers,__connect.errors.partition:0,__connect.errors.offset:6,__connect.errors.connector.name:sqlserver-sink,__connect.errors.task.id:0,__connect.errors.stage:TASK_PUT,__connect.errors.class.name:org.apache.kafka.connect.sink.SinkTask,__connect.errors.exception.class.name:io.confluent.connect.jdbc.sink.TableAlterOrCreateException,__connect.errors.exception.message:Cannot ALTER TABLE "dbo"."customers" to add missing field SinkRecordField{schema=Schema{STRING}, name='last_name', isPrimaryKey=false}, as the field is not optional and does not have a default value,__connect.errors.exception.stacktrace:io.confluent.connect.jdbc.sink.TableAlterOrCreateException: Cannot ALTER TABLE "dbo"."customers" to add missing field SinkRecordField{schema=Schema{STRING}, name='last_name', isPrimaryKey=false}, as the field is not optional and does not have a default value
#         at io.confluent.connect.jdbc.sink.DbStructure.amendIfNecessary(DbStructure.java:182)
#         at io.confluent.connect.jdbc.sink.DbStructure.createOrAmendIfNecessary(DbStructure.java:83)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:123)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.unrollAndRetry(JdbcSinkTask.java:133)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:87)
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
#         �
# JohnDoe2*john.2doe@example.com+1-555-123456

log "alter table (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/alter-table.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Create new capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/create-new-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

sleep 5

log "Make an insert with phone_number"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email,phone_number) VALUES ('John','Doe','john.doe@example.com', '+1-555-123456');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers, we should see the message with the phone_number"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 6

log "Check DLQ"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic dlq --from-beginning --property print.headers=true

# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1006,"first_name":"John","last_name":"Doe","email":"john.doe@example.com","phone_number":{"string":"+1-555-123456"}}},"source":{"version":"1.5.0.Final","connector":"sqlserver","name":"server1","ts_ms":1626081244747,"snapshot":{"string":"false"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":{"string":"00000025:00000d48:0003"},"commit_lsn":{"string":"00000025:00000d48:0005"},"event_serial_no":{"long":1}},"op":"c","ts_ms":{"long":1626081249542},"transaction":null}

log "Drop old capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/drop-old-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "JDBC SINK: Show content of customers table, we should see the message with the phone_number"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;
select * from master.dbo.customers
GO
EOF
cat /tmp/result.log

log "alter table by removing last_name column (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-97960/alter-table.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Create new capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-97960/create-new-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

sleep 5

log "alter destination table to drop column (JDBC sink is not doing it automatically) https://docs.confluent.io/kafka-connect-jdbc/current/sink-connector/index.html#auto-creation-and-auto-evolution"
cat ./repro-97960/alter-dest-table-drop-column.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Make an insert without last_name"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,email,phone_number) VALUES ('Vincent','vincent@example.com', '+1-555-123456');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers, we should see the message without the last_name"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 7


log "Drop old capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-97960/drop-old-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "JDBC SINK: Show content of customers table, we should not see anymore the column last_name"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;
select * from master.dbo.customers
GO
EOF
cat /tmp/result.log

# [2022-04-04 08:48:00,907] ERROR [sqlserver-sink|task-0] WorkerSinkTask{id=sqlserver-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask:627)
# org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Cannot insert the value NULL into column 'last_name', table 'master.dbo.customers'; column does not allow nulls. UPDATE fails.

# 	at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:108)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception chain:
# java.sql.BatchUpdateException: Cannot insert the value NULL into column 'last_name', table 'master.dbo.customers'; column does not allow nulls. UPDATE fails.

# 	at io.confluent.connect.jdbc.sink.JdbcSinkTask.getAllMessagesException(JdbcSinkTask.java:150)
# 	at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:102)
# 	... 11 more

