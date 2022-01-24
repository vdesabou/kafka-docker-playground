#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89414-from-debezium-postgres-cdc-to-jdbc-postgres.yml"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"

docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

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
               "wal_level": "logical",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "transforms": "unwrap",
               "transforms": "unwrap",
               "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .



sleep 5

log "Verifying topic asgard.public.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers --from-beginning --property print.key=true --max-messages 5


log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "asgard.public.customers",
               "auto.create": "true",
               "table.name.format": "my_output_table"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Show content of my_output_table table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM my_output_table'" > /tmp/result.log  2>&1
cat /tmp/result.log

# without SMT:

# 2022-01-24 13:43:44,278] ERROR [postgres-sink|task-0] WorkerSinkTask{id=postgres-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
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
# Caused by: org.apache.kafka.connect.errors.ConnectException: asgard.public.customers.Value (STRUCT) type doesn't have a mapping to the SQL database column type
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.getSqlType(GenericDatabaseDialect.java:1918)
#         at io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect.getSqlType(PostgreSqlDatabaseDialect.java:332)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.writeColumnSpec(GenericDatabaseDialect.java:1834)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.lambda$writeColumnsSpec$39(GenericDatabaseDialect.java:1823)
#         at io.confluent.connect.jdbc.util.ExpressionBuilder.append(ExpressionBuilder.java:560)
#         at io.confluent.connect.jdbc.util.ExpressionBuilder$BasicListBuilder.of(ExpressionBuilder.java:599)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.writeColumnsSpec(GenericDatabaseDialect.java:1825)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.buildCreateTableStatement(GenericDatabaseDialect.java:1742)
#         at io.confluent.connect.jdbc.sink.DbStructure.create(DbStructure.java:121)
#         at io.confluent.connect.jdbc.sink.DbStructure.createOrAmendIfNecessary(DbStructure.java:67)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.add(BufferedRecords.java:123)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more