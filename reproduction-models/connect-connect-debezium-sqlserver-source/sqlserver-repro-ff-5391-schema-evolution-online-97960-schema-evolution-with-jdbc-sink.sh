#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-ff-5391-schema-evolution-online-97960-schema-evolution-with-jdbc-sink.yml"


log "Load ./repro-ff-5391/inventory.sql to SQL Server"
cat ./repro-ff-5391/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "workaround: set compatibility to NONE"
curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data '{"compatibility": "NONE"}' http://localhost:8081/config/server1.dbo.customers-value

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

               "key.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",

               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.object.additional.properties" : "false",

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
timeout 60 docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5

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
               "key.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "auto.create": "true",
               "auto.evolve": "true",
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
select * from dbo.customers
GO
EOF
cat /tmp/result.log

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
timeout 60 docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 6

# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1006,"first_name":"John","last_name":"Doe","email":"john.doe@example.com","phone_number":{"string":"+1-555-123456"}}},"source":{"version":"1.5.0.Final","connector":"sqlserver","name":"server1","ts_ms":1626081244747,"snapshot":{"string":"false"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":{"string":"00000025:00000d48:0003"},"commit_lsn":{"string":"00000025:00000d48:0005"},"event_serial_no":{"long":1}},"op":"c","ts_ms":{"long":1626081249542},"transaction":null}

log "Drop old capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/drop-old-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "JDBC SINK: Show content of customers table, we should see the message with the phone_numbe"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from dbo.customers
GO
EOF
cat /tmp/result.log

# without "value.converter.object.additional.properties" : "false" and default compatibility BACKWARD
# [2022-03-22 12:05:48,051] ERROR [debezium-sqlserver-source|task-0] WorkerSourceTask{id=debezium-sqlserver-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: org.apache.kafka.connect.errors.DataException: Converting Kafka Connect data to byte[] failed due to serialization error of topic server1.dbo.customers: 
#         at io.confluent.connect.json.JsonSchemaConverter.fromConnectData(JsonSchemaConverter.java:92)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$4(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 11 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error registering JSON schema: {"type":"object","title":"server1.dbo.customers.Envelope","properties":{"op":{"type":"string","connect.index":3},"before":{"connect.index":0,"oneOf":[{"type":"null"},{"type":"object","title":"server1.dbo.customers.Value","properties":{"last_name":{"type":"string","connect.index":2},"phone_number":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"string"}]},"id":{"type":"integer","connect.index":0,"connect.type":"int32"},"first_name":{"type":"string","connect.index":1},"email":{"type":"string","connect.index":3}}}]},"after":{"connect.index":1,"oneOf":[{"type":"null"},{"type":"object","title":"server1.dbo.customers.Value","properties":{"last_name":{"type":"string","connect.index":2},"phone_number":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"string"}]},"id":{"type":"integer","connect.index":0,"connect.type":"int32"},"first_name":{"type":"string","connect.index":1},"email":{"type":"string","connect.index":3}}}]},"source":{"type":"object","title":"io.debezium.connector.sqlserver.Source","connect.index":2,"properties":{"schema":{"type":"string","connect.index":7},"sequence":{"connect.index":6,"oneOf":[{"type":"null"},{"type":"string"}]},"event_serial_no":{"connect.index":11,"oneOf":[{"type":"null"},{"type":"integer","connect.type":"int64"}]},"connector":{"type":"string","connect.index":1},"name":{"type":"string","connect.index":2},"commit_lsn":{"connect.index":10,"oneOf":[{"type":"null"},{"type":"string"}]},"change_lsn":{"connect.index":9,"oneOf":[{"type":"null"},{"type":"string"}]},"version":{"type":"string","connect.index":0},"ts_ms":{"type":"integer","connect.index":3,"connect.type":"int64"},"snapshot":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"string","title":"io.debezium.data.Enum","default":"false","connect.version":1,"connect.parameters":{"allowed":"true,last,false,incremental"}}]},"db":{"type":"string","connect.index":5},"table":{"type":"string","connect.index":8}}},"ts_ms":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"integer","connect.type":"int64"}]},"transaction":{"connect.index":5,"oneOf":[{"type":"null"},{"type":"object","properties":{"data_collection_order":{"type":"integer","connect.index":2,"connect.type":"int64"},"id":{"type":"string","connect.index":0},"total_order":{"type":"integer","connect.index":1,"connect.type":"int64"}}}]}}}
#         at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.toKafkaException(AbstractKafkaSchemaSerDe.java:259)
#         at io.confluent.kafka.serializers.json.AbstractKafkaJsonSchemaSerializer.serializeImpl(AbstractKafkaJsonSchemaSerializer.java:141)
#         at io.confluent.connect.json.JsonSchemaConverter$Serializer.serialize(JsonSchemaConverter.java:149)
#         at io.confluent.connect.json.JsonSchemaConverter.fromConnectData(JsonSchemaConverter.java:90)
#         ... 15 more
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Schema being registered is incompatible with an earlier schema for subject "server1.dbo.customers-value"; error code: 409
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:297)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:367)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:544)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:532)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:490)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.registerAndGetId(CachedSchemaRegistryClient.java:257)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:366)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:337)
#         at io.confluent.kafka.serializers.json.AbstractKafkaJsonSchemaSerializer.serializeImpl(AbstractKafkaJsonSchemaSerializer.java:106)
#         ... 17 more



log "alter table by removing last_name column (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-97960/alter-table.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Create new capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-97960/create-new-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

sleep 5

log "Make an insert without last_name"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,email,phone_number) VALUES ('Vincent','vincent@example.com', '+1-555-123456');
GO
EOF

# expected because FORWARD_TRANSITIVE is set and removing a mandatory column is not forxward compatible
# [2022-03-22 14:12:36,548] ERROR [debezium-sqlserver-source|task-0] WorkerSourceTask{id=debezium-sqlserver-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: org.apache.kafka.connect.errors.DataException: Converting Kafka Connect data to byte[] failed due to serialization error of topic server1.dbo.customers: 
#         at io.confluent.connect.json.JsonSchemaConverter.fromConnectData(JsonSchemaConverter.java:92)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$4(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 11 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error registering JSON schema: {"type":"object","title":"server1.dbo.customers.Value","properties":{"phone_number":{"connect.index":3,"oneOf":[{"type":"null"},{"type":"string"}]},"id":{"type":"integer","connect.index":0,"connect.type":"int32"},"first_name":{"type":"string","connect.index":1},"email":{"type":"string","connect.index":2}}}
#         at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.toKafkaException(AbstractKafkaSchemaSerDe.java:259)
#         at io.confluent.kafka.serializers.json.AbstractKafkaJsonSchemaSerializer.serializeImpl(AbstractKafkaJsonSchemaSerializer.java:141)
#         at io.confluent.connect.json.JsonSchemaConverter$Serializer.serialize(JsonSchemaConverter.java:149)
#         at io.confluent.connect.json.JsonSchemaConverter.fromConnectData(JsonSchemaConverter.java:90)
#         ... 15 more
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Schema being registered is incompatible with an earlier schema for subject "server1.dbo.customers-value"; error code: 409
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:297)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:367)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:544)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:532)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:490)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.registerAndGetId(CachedSchemaRegistryClient.java:257)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:366)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:337)
#         at io.confluent.kafka.serializers.json.AbstractKafkaJsonSchemaSerializer.serializeImpl(AbstractKafkaJsonSchemaSerializer.java:106)
#         ... 17 more


# with  "value.converter.object.additional.properties" : "false" and BACKWARD, I get:

# [2022-03-22 14:19:08,563] ERROR [debezium-sqlserver-source|task-0] WorkerSourceTask{id=debezium-sqlserver-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: org.apache.kafka.connect.errors.DataException: Converting Kafka Connect data to byte[] failed due to serialization error of topic server1.dbo.customers: 
#         at io.confluent.connect.json.JsonSchemaConverter.fromConnectData(JsonSchemaConverter.java:92)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$4(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 11 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error registering JSON schema: {"type":"object","additionalProperties":false,"title":"server1.dbo.customers.Value","properties":{"phone_number":{"connect.index":3,"oneOf":[{"type":"null"},{"type":"string"}]},"id":{"type":"integer","connect.index":0,"connect.type":"int32"},"first_name":{"type":"string","connect.index":1},"email":{"type":"string","connect.index":2}}}
#         at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.toKafkaException(AbstractKafkaSchemaSerDe.java:259)
#         at io.confluent.kafka.serializers.json.AbstractKafkaJsonSchemaSerializer.serializeImpl(AbstractKafkaJsonSchemaSerializer.java:141)
#         at io.confluent.connect.json.JsonSchemaConverter$Serializer.serialize(JsonSchemaConverter.java:149)
#         at io.confluent.connect.json.JsonSchemaConverter.fromConnectData(JsonSchemaConverter.java:90)
#         ... 15 more
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Schema being registered is incompatible with an earlier schema for subject "server1.dbo.customers-value"; error code: 409
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:297)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:367)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:544)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:532)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:490)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.registerAndGetId(CachedSchemaRegistryClient.java:257)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:366)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:337)
#         at io.confluent.kafka.serializers.json.AbstractKafkaJsonSchemaSerializer.serializeImpl(AbstractKafkaJsonSchemaSerializer.java:106)
#         ... 17 more

sleep 5

log "Verifying topic server1.dbo.customers, we should see the message without the last_name"
timeout 60 docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 7


log "Drop old capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-97960/drop-old-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "JDBC SINK: Show content of customers table, we should see the message with the phone_numbe"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from dbo.customers
GO
EOF
cat /tmp/result.log


# [2022-03-22 14:38:49,426] WARN [sqlserver-sink|task-0] Write of 1 records failed, remainingRetries=8 (io.confluent.connect.jdbc.sink.JdbcSinkTask:92)
# java.sql.BatchUpdateException: Cannot insert the value NULL into column 'last_name', table 'master.dbo.customers'; column does not allow nulls. UPDATE fails.
#         at net.sourceforge.jtds.jdbc.JtdsStatement.executeBatch(JtdsStatement.java:1069)
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
