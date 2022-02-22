#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-81246.yml"


log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"
docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments, curr_amount) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management', 1.4);"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.debezium.connector \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

log "Creating Debezium PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "myuser",
                    "database.password": "mypassword",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw",
                    "decimal.handling.mode": "double",
                    "schema.refresh.mode": "columns_diff",
                    "event.processing.failure.handling.mode": "fail",
                    "include.unknown.datatypes": "true",
                    "plugin.name": "pgoutput"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .



sleep 5

log "Verifying topic asgard.public.customers-raw"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --max-messages 5

# With latest (1.7.1):  no Cannot parse column default value 'NULL::numeric' to type 'numeric', but "curr_amount":"1.2"

# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)


# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642781519530266},"update_ts":{"long":1642781519530266},"curr_amount":1.2}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642781556064,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24525144\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24525144},"xmin":null},"op":"r","ts_ms":{"long":1642781556069},"transaction":null}

# with 1.6.3 -> "curr_amount":"1.2"
# [2022-01-21 16:01:53,106] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 16:01:53,107] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 16:01:53,107] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'NULL::numeric' to type 'numeric'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)

# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642781643548279},"update_ts":{"long":1642781643548279},"curr_amount":1.2}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642781679777,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24522696\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24522696},"xmin":null},"op":"r","ts_ms":{"long":1642781679782},"transaction":null}

# With 1.4.1: no Cannot parse column default value at all and "curr_amount":"1.2"

# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642781817800503},"update_ts":{"long":1642781817800503},"curr_amount":1.2}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642781853914,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24527280},"xmin":null},"op":"r","ts_ms":{"long":1642781853917},"transaction":null}


log "Adding an element to the table"
docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments, curr_amount) values (303, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management', 1.4);"

# with connector 1.6.2
# [2022-01-21 17:17:35,621] ERROR WorkerSourceTask{id=debezium-postgres-source-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: An exception occurred in the change event producer. This connector will be stopped.
#         at io.debezium.pipeline.ErrorHandler.setProducerThrowable(ErrorHandler.java:42)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.execute(PostgresStreamingChangeEventSource.java:168)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.execute(PostgresStreamingChangeEventSource.java:40)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.streamEvents(ChangeEventSourceCoordinator.java:160)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:122)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: org.apache.kafka.connect.errors.SchemaBuilderException: Invalid default value
#         at org.apache.kafka.connect.data.SchemaBuilder.defaultValue(SchemaBuilder.java:131)
#         at io.debezium.relational.TableSchemaBuilder.addField(TableSchemaBuilder.java:374)
#         at io.debezium.relational.TableSchemaBuilder.lambda$create$2(TableSchemaBuilder.java:119)
#         at java.util.stream.ForEachOps$ForEachOp$OfRef.accept(ForEachOps.java:184)
#         at java.util.stream.ReferencePipeline$2$1.accept(ReferencePipeline.java:175)
#         at java.util.ArrayList$ArrayListSpliterator.forEachRemaining(ArrayList.java:1382)
#         at java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:482)
#         at java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:472)
#         at java.util.stream.ForEachOps$ForEachOp.evaluateSequential(ForEachOps.java:151)
#         at java.util.stream.ForEachOps$ForEachOp$OfRef.evaluateSequential(ForEachOps.java:174)
#         at java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
#         at java.util.stream.ReferencePipeline.forEach(ReferencePipeline.java:418)
#         at io.debezium.relational.TableSchemaBuilder.create(TableSchemaBuilder.java:117)
#         at io.debezium.relational.RelationalDatabaseSchema.buildAndRegisterSchema(RelationalDatabaseSchema.java:130)
#         at io.debezium.relational.RelationalDatabaseSchema.refreshSchema(RelationalDatabaseSchema.java:204)
#         at io.debezium.relational.RelationalDatabaseSchema.refresh(RelationalDatabaseSchema.java:195)
#         at io.debezium.connector.postgresql.PostgresSchema.applySchemaChangesForTable(PostgresSchema.java:232)
#         at io.debezium.connector.postgresql.connection.pgoutput.PgOutputMessageDecoder.handleRelationMessage(PgOutputMessageDecoder.java:326)
#         at io.debezium.connector.postgresql.connection.pgoutput.PgOutputMessageDecoder.processNotEmptyMessage(PgOutputMessageDecoder.java:176)
#         at io.debezium.connector.postgresql.connection.AbstractMessageDecoder.processMessage(AbstractMessageDecoder.java:33)
#         at io.debezium.connector.postgresql.connection.PostgresReplicationConnection$1.deserializeMessages(PostgresReplicationConnection.java:493)
#         at io.debezium.connector.postgresql.connection.PostgresReplicationConnection$1.readPending(PostgresReplicationConnection.java:485)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.processMessages(PostgresStreamingChangeEventSource.java:203)
#         at io.debezium.connector.postgresql.PostgresStreamingChangeEventSource.execute(PostgresStreamingChangeEventSource.java:165)
#         ... 8 more
# Caused by: org.apache.kafka.connect.errors.DataException: Invalid Java object for schema type FLOAT64: class java.math.BigDecimal for field: "null"
#         at org.apache.kafka.connect.data.ConnectSchema.validateValue(ConnectSchema.java:240)
#         at org.apache.kafka.connect.data.ConnectSchema.validateValue(ConnectSchema.java:213)
#         at org.apache.kafka.connect.data.SchemaBuilder.defaultValue(SchemaBuilder.java:129)
#         ... 31 more
# [2022-01-21 17:17:35,622] ERROR WorkerSourceTask{id=debezium-postgres-source-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# [2022-01-21 17:17:35,622] INFO Stopping down connector (io.debezium.connector.common.BaseSourceTask)

# with debezium/debezium-connector-postgresql:1.7.1, it works ok

# [2022-01-24 10:19:30,206] INFO [debezium-postgres-source|task-0] Processing messages (io.debezium.connector.postgresql.PostgresStreamingChangeEventSource:200)
# [2022-01-24 10:19:30,207] INFO [debezium-postgres-source|task-0] Message with LSN 'LSN{0/175E338}' arrived, switching off the filtering (io.debezium.connector.postgresql.connection.WalPositionLocator:134)
# [2022-01-24 10:19:30,217] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:91)
# [2022-01-24 10:19:30,217] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:91)
# [2022-01-24 10:19:30,220] WARN [debezium-postgres-source|task-0] Primary keys are not defined for table 'customers', defaulting to unique indices (io.debezium.connector.postgresql.connection.pgoutput.PgOutputMessageDecoder:280)
# [2022-01-24 10:19:30,407] INFO [debezium-postgres-source|task-0] 22 records sent during previous 00:00:11.421, last recorded offset: {transaction_id=null, lsn_proc=24503096, lsn=24503096, txId=582, ts_usec=1643019569946425} (io.debezium.connector.common.BaseSourceTask:185)

log "Verifying topic asgard.public.customers-raw"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --max-messages 5

# null    {"before":null,"after":{"asgard.public.customers.Value":{"id":{"int":1},"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1643019087074551},"update_ts":{"long":1643019087074551},"curr_amount":1.2,"trans_dollar_amt":0.0}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1643019122135,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24503000\"]"},"schema":"public","table":"customers","txId":{"long":581},"lsn":{"long":24503000},"xmin":null},"op":"r","ts_ms":{"long":1643019122138},"transaction":null}
# null    {"before":null,"after":{"asgard.public.customers.Value":{"id":{"int":2},"first_name":{"string":"Ruthie"},"last_name":{"string":"Brockherst"},"email":{"string":"rbrockherst1@ow.ly"},"gender":{"string":"Female"},"club_status":{"string":"platinum"},"comments":{"string":"Reverse-engineered tangible interface"},"create_ts":{"long":1643019087076220},"update_ts":{"long":1643019087076220},"curr_amount":1.2,"trans_dollar_amt":0.0}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1643019122141,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24503000\"]"},"schema":"public","table":"customers","txId":{"long":581},"lsn":{"long":24503000},"xmin":null},"op":"r","ts_ms":{"long":1643019122141},"transaction":null}
# null    {"before":null,"after":{"asgard.public.customers.Value":{"id":{"int":3},"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"email":{"string":"mcocci2@techcrunch.com"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Multi-tiered bandwidth-monitored capability"},"create_ts":{"long":1643019087077677},"update_ts":{"long":1643019087077677},"curr_amount":1.2,"trans_dollar_amt":0.0}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1643019122142,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24503000\"]"},"schema":"public","table":"customers","txId":{"long":581},"lsn":{"long":24503000},"xmin":null},"op":"r","ts_ms":{"long":1643019122142},"transaction":null}
# null    {"before":null,"after":{"asgard.public.customers.Value":{"id":{"int":4},"first_name":{"string":"Hashim"},"last_name":{"string":"Rumke"},"email":{"string":"hrumke3@sohu.com"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Self-enabling 24/7 firmware"},"create_ts":{"long":1643019087079155},"update_ts":{"long":1643019087079155},"curr_amount":1.2,"trans_dollar_amt":0.0}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1643019122143,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24503000\"]"},"schema":"public","table":"customers","txId":{"long":581},"lsn":{"long":24503000},"xmin":null},"op":"r","ts_ms":{"long":1643019122143},"transaction":null}
# null    {"before":null,"after":{"asgard.public.customers.Value":{"id":{"int":5},"first_name":{"string":"Hansiain"},"last_name":{"string":"Coda"},"email":{"string":"hcoda4@senate.gov"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Centralized full-range approach"},"create_ts":{"long":1643019087080269},"update_ts":{"long":1643019087080269},"curr_amount":1.2,"trans_dollar_amt":0.0}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1643019122143,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24503000\"]"},"schema":"public","table":"customers","txId":{"long":581},"lsn":{"long":24503000},"xmin":null},"op":"r","ts_ms":{"long":1643019122143},"transaction":null}