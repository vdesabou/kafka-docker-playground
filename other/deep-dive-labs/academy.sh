#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/academy: runs the reproduction models of the beginner and advanced exercises
# (academy/) and asserts the failure each exercise is about, then the fix the page gives. The intermediate exercise (S3
# sink, StackOverflowError) needs an AWS account: replayed only when AWS credentials are available
lab_require_plaintext
academy="${DIR}/../../academy"

# the models fail on purpose (connector create-or-update stops at the FAILED task): their exit code is not checked
function run_model () {
    lab_run bash -c "cd '$academy/$1' && bash '$2'"
}

log "Exercise 1: Avro Converter: Unknown magic byte"
run_model connect-connect-filestream-sink filestream-sink-repro-000002-deserialization-error.sh
lab_run playground connector status --connector filestream-sink
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID"
lab_expect_contains "Caused by: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_run playground topic consume --topic filestream
lab_expect_contains "it contains 5 messages"
lab_expect_contains "|Partition:0|Offset:4|"
lab_expect_contains "1 record(s) of topic filestream could not be deserialized and were skipped"
lab_run playground consumer-group describe --group connect-filestream-sink
lab_expect_contains "Consumer group 'connect-filestream-sink' has no active members."

log "Exercise 1, Step 4: with a dead letter queue"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "errors.tolerance": "all",
     "errors.deadletterqueue.topic.name": "dlq",
     "errors.deadletterqueue.topic.replication.factor": "1",
     "errors.deadletterqueue.context.headers.enable": "true",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF
# no offset was committed: the task reads the topic from the beginning again
playground connector restart --connector filestream-sink
sleep 10
lab_run playground topic dlq inspect --topic dlq --no-open
lab_expect_contains "🔢 1 record(s) of connector filestream-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)"
lab_expect_contains "🌱 root cause: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_expect_contains "📍 original records: topic filestream partition 0 offsets 3..3 (1)"
lab_expect_contains '🔎 sample value: {"u_name": "poison pill", "u_price": 1.75, "u_quantity": 1}'
lab_run bash -c "docker exec connect cat /tmp/output.json | grep -c '^Struct{u_name='"
lab_expect_equals "$LAB_OUTPUT" "4" "valid records in the output file"

log "Exercise 2: InsertField SMT, sink connector"
run_model connect-connect-filestream-sink filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh
lab_run playground connector status --connector filestream-sink
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"
lab_run playground connector smt test --no-open --connector filestream-sink --from-topic filestream --offset 0
lab_expect_contains 'step 1  InsertField$Value "InsertField"'
lab_expect_contains "❌ org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"
lab_expect_contains "❌ the chain stopped at step 1"
chain_file=$(mktemp)
trap 'rm -f "$chain_file"' EXIT
cat > "$chain_file" << 'EOF'
{
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "InsertField",
  "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertField.static.field": "MessageSource",
  "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF
lab_run playground connector smt test --no-open --config @"$chain_file" --from-topic filestream --offset 0
lab_expect_contains '"MessageSource":"Kafka Connect framework"'
lab_expect_contains "✅ result: topic filestream, key null"

log "Exercise 2, Step 3: with a dead letter queue"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertField.static.field": "MessageSource",
     "transforms.InsertField.static.value": "Kafka Connect framework",
     "errors.tolerance": "all",
     "errors.deadletterqueue.topic.name": "dlq",
     "errors.deadletterqueue.topic.replication.factor": "1",
     "errors.deadletterqueue.context.headers.enable": "true",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF
playground connector restart --connector filestream-sink
sleep 10
lab_run playground topic dlq inspect --topic dlq --no-open
lab_expect_contains "🔢 1 record(s) of connector filestream-sink, stage TRANSFORMATION (org.apache.kafka.connect.runtime.TransformationStage)"
lab_expect_contains "❌ org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"

log "Exercise 2, Steps 4 and 5: JsonConverter, then the topic, offset, partition and timestamp"
# like the page: the example runs again (a fresh environment), with the fixed config: the record of the model is processed
run_model connect-connect-filestream-sink filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertField.static.field": "MessageSource",
     "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF
playground connector restart --connector filestream-sink
sleep 10
lab_run docker exec connect cat /tmp/output.json
lab_expect_contains "MessageSource=Kafka Connect framework"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "transforms": "InsertTopic,InsertOffset,InsertPartition,InsertTimestamp,TimestampConverter",
     "transforms.InsertOffset.offset.field": "__kafka_offset",
     "transforms.InsertOffset.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertPartition.partition.field": "__kafka_partition",
     "transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
     "transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertTopic.topic.field": "__kafka_topic",
     "transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
     "transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
     "transforms.TimestampConverter.target.type": "string",
     "transforms.TimestampConverter.field": "__kafka_ts"
}
EOF
playground topic produce -t filestream --nb-messages 1 << 'EOF'
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
sleep 10
lab_run docker exec connect tail -1 /tmp/output.json
lab_expect_contains "__kafka_topic=filestream, __kafka_partition=0"
lab_expect_contains "__kafka_offset=1"
lab_run bash -c "docker exec connect tail -1 /tmp/output.json | grep -oE '__kafka_ts=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}'"
lab_expect_contains "__kafka_ts=" "__kafka_ts in the format yyyy-MM-dd HH:mm:ss.SSS"

log "Exercise 3: InsertField SMT, source connector"
run_model connect-connect-filestream-source filestream-source-repro-000004-insertfield-smt-dataexception-only-struct-objects-supported.sh
lab_run playground connector status --connector filestream-source
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"
lab_run playground container logs -c connect --grep "Executing stage 'TRANSFORMATION'" --no-follow
lab_expect_contains "Executing stage 'TRANSFORMATION' with class 'org.apache.kafka.connect.runtime.TransformationStage'"
lab_expect_contains "valueSchema=Schema{STRING}"

log "Exercise 4: InsertField SMT, adding topic, offset and partition with a source connector"
run_model connect-connect-jdbc-mysql-source "mysql-repro-000005-insertfield-smt:-adding-topic-offset-and-partition-not-working.sh"
lab_run playground connector status --connector mysql-source
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Only SinkRecord supported for [field insertion], found: org.apache.kafka.connect.source.SourceRecord"
lab_run playground connector smt test --no-open --connector mysql-source --record '{"topic":"mysql-team","value":{"id":102,"name":"another"}}'
lab_expect_contains "on a source record"
lab_expect_contains 'step 1  InsertField$Value "InsertTopic"'
lab_expect_contains 'step 2  InsertField$Value "InsertOffset"'
lab_expect_contains "❌ the chain stopped at step 2"
lab_run playground container logs -c connect --grep "Applying transformation" --no-follow
lab_expect_contains "Applying transformation org.apache.kafka.connect.transforms.InsertField\$Value to SourceRecord"
lab_expect_contains "__kafka_topic=mysql-team}"

log "Exercise 4, Steps 3 and 4: without InsertOffset, partition and timestamp are null"
playground connector create-or-update --connector mysql-source << 'EOF'
{
  "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max":"1",
  "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false",
  "table.whitelist":"team",
  "mode":"timestamp+incrementing",
  "timestamp.column.name":"last_modified",
  "incrementing.column.name":"id",
  "topic.prefix":"mysql-",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true",
  "transforms": "InsertTopic,InsertPartition,InsertTimestamp,TimestampConverter",
  "transforms.InsertPartition.partition.field": "__kafka_partition",
  "transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
  "transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertTopic.topic.field": "__kafka_topic",
  "transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
  "transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
  "transforms.TimestampConverter.target.type": "string",
  "transforms.TimestampConverter.field": "__kafka_ts"
}
EOF
playground connector restart --connector mysql-source
sleep 10
lab_run playground connector status --connector mysql-source
lab_expect_contains "0:🟢 RUNNING"
lab_run playground topic consume --topic mysql-team --max-messages 2
lab_expect_contains '"__kafka_topic":{"string":"mysql-team"},"__kafka_partition":null,"__kafka_ts":null'

log "Exercise 6 (advanced): JDBC sink RUNNING, but no data in the table"
run_model connect-connect-jdbc-postgresql-sink postgres-sink-repro-000006-sink-running-but-no-data.sh
lab_expect_contains "postgres-sink                  ✅ RUNNING  0:🟢 RUNNING"
lab_run playground connector diagnose --connector postgres-sink --no-open
lab_expect_contains "✅ no ERROR/FATAL record found"
lab_expect_contains "🐌 RUNNING but no progress? run this command again, then take a thread dump if lag or offsets do not move"
lab_run playground connector show-lag --connector postgres-sink --once
lab_expect_contains "is not available (no offset committed yet)"
lab_run playground analyze thread-dump --container connect --output-dir /tmp/academy-lab-thread-dump
lab_expect_contains 'Connect task thread "task-thread-postgres-sink-0" is RUNNABLE on the same frames in all 3 dumps'
lab_expect_contains "It is inside io.confluent.connect.jdbc.sink.JdbcSinkTask.put, in a socket read: the sink waits for its external system"
lab_run playground db sql << 'EOF'
SELECT application_name, state, wait_event_type, cardinality(pg_blocking_pids(pid)) AS nb_blockers
FROM pg_stat_activity
WHERE datname = 'postgres' AND pid <> pg_backend_pid()
ORDER BY xact_start;
EOF
lab_expect_contains "nightly-batch | idle in transaction"
lab_expect_contains "PostgreSQL JDBC Driver | active | Lock | 1"
lab_run playground db sql << 'EOF'
SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = 'nightly-batch';
EOF
sleep 20
lab_run playground connector show-lag --connector postgres-sink --once
lab_expect_contains "consumer lag for 🌎onprem connector postgres-sink is 0"
lab_run playground db sql << 'EOF'
SELECT count(*) FROM orders;
EOF
lab_expect_contains "10"

log "Exercise 7 (advanced): JDBC sink, duplicates in the table after a worker crash"
run_model connect-connect-jdbc-postgresql-sink postgres-sink-repro-000007-duplicates-after-worker-crash.sh
lab_run playground connector reconcile --connector postgres-sink
lab_expect_contains "🛢️ table orders 20 row(s)"
lab_expect_contains "❌ Duplicated: 10"
lab_expect_contains "❌ duplicated: the same record is there several times"
lab_run playground container logs -c connect --grep "offset.flush.interval.ms" --no-follow
lab_expect_contains "offset.flush.interval.ms = 60000"
playground connector create-or-update --connector postgres-sink-upsert << 'EOF'
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "table.name.format": "orders_upsert",
  "auto.create": "true",
  "insert.mode": "upsert",
  "pk.mode": "record_value",
  "pk.fields": "id"
}
EOF
playground db wait-for-rows --table orders_upsert --min-expected-rows 10
playground container kill --container connect
playground container restart --container connect
playground container wait-for-connect-rest-api-ready
# the task of the upsert connector reads the 10 records again once the member of the killed worker has timed out
sleep 90
lab_run playground connector reconcile --connector postgres-sink-upsert
lab_expect_contains "🔑 key: id (pk.fields, pk.mode record_value)"
lab_expect_contains "✅ complete: every record is on the other side, with the same values"
lab_run playground db sql << 'EOF'
SELECT count(*) AS nb_rows, count(DISTINCT id) AS nb_ids FROM orders_upsert;
EOF
lab_expect_contains "10 | 10"

log "Exercise 8 (advanced): HTTP sink timeouts, is it the server or the network?"
run_model connect-connect-http-sink http-sink-repro-000008-http-sink-timeouts-slow-network.sh
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "java.net.SocketTimeoutException: Read timed out"
lab_run playground tools http-server requests
lab_expect_contains "📥 3 request(s) received since the start or the last reset"
lab_expect_contains "answers: 200 after 0 ms"
capture_log=$(mktemp)
pcap_dir=$(mktemp -d)
(playground debug tcp-dump --container connect --port 9006 --duration 25 --no-open --output-dir "$pcap_dir" > "$capture_log" 2>&1 &)
sleep 5
playground connector restart --connector http-sink
sleep 35
lab_run cat "$capture_log"
lab_expect_contains "HTTP response(s) of POST / on httpserver:9006 arrived after the client gave up: the server answered after 150"
lab_expect_contains "but the client closed the connection after 100"
lab_expect_contains "handshake (SYN → SYN/ACK): p50 150"
lab_expect_contains "reset(s) connect → httpserver:9006 on established connection(s)"
lab_run playground debug degrade-traffic --container httpserver --action status
lab_expect_contains "delay 1.5s"
playground debug degrade-traffic --container httpserver --action stop
playground tools http-server reset
playground tools http-server set-response --status-code 200
playground connector restart --connector http-sink
sleep 20
lab_run playground connector status --connector http-sink
lab_expect_contains "0:🟢 RUNNING"
lab_run playground tools http-server requests --grep '"id":10'
lab_expect_contains '"id":10'

log "Exercise 5 (intermediate): StackOverflowError with S3 sink connector"
if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_PROFILE" ] && [ ! -f "$HOME/.aws/credentials" ]
then
    logwarn "no AWS credentials (AWS_ACCESS_KEY_ID, AWS_PROFILE or ~/.aws/credentials): exercise 5 (S3 sink) is not replayed"
else
    run_model connect-connect-aws-s3-sink s3-sink-repro-000001-stackoverflowerror-with-s3-sink-connector.sh
    lab_run playground connector status --connector s3-sink
    lab_expect_contains "0:🛑 FAILED"
    lab_expect_contains "Caused by: java.lang.StackOverflowError"
    lab_expect_contains "at org.apache.parquet.avro.AvroSchemaConverter.convertUnion"
fi

log "Exercise 9 (advanced): Debezium PostgreSQL, the replication slot keeps growing"
run_model connect-connect-debezium-postgresql-source debezium-postgres-source-repro-000009-replication-slot-keeps-growing.sh
lab_expect_contains "debezium-postgres-source       ✅ RUNNING  0:🟢 RUNNING"
lab_run playground db cdc-check
lab_expect_contains "slot debezium (pgoutput) active,"
lab_expect_contains "MB behind"
lab_run playground db sql << 'EOF'
SELECT CASE WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) > 100000000 THEN 'more than 100 MB retained' ELSE 'less than 100 MB retained' END AS slot FROM pg_replication_slots WHERE slot_name = 'debezium';
EOF
lab_expect_contains "more than 100 MB retained"
playground db sql << 'EOF'
CREATE TABLE debezium_heartbeat (id INT PRIMARY KEY, ts TIMESTAMP);
EOF
playground connector create-or-update --connector debezium-postgres-source << 'EOF'
{
     "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
     "tasks.max": "1",
     "database.hostname": "postgres",
     "database.port": "5432",
     "database.user": "myuser",
     "database.password": "mypassword",
     "database.dbname" : "postgres",
     "topic.prefix": "asgard",
     "plugin.name": "pgoutput",
     "slot.name": "debezium",
     "publication.autocreate.mode": "filtered",
     "table.include.list": "public.customers,public.debezium_heartbeat",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "key.converter.schemas.enable": "false",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "heartbeat.interval.ms": "10000",
     "heartbeat.action.query": "INSERT INTO debezium_heartbeat (id, ts) VALUES (1, now()) ON CONFLICT (id) DO UPDATE SET ts = now()"
}
EOF
sleep 90
lab_run playground db sql << 'EOF'
SELECT CASE WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) < 1000000 THEN 'slot caught up' ELSE 'slot still behind' END AS slot FROM pg_replication_slots WHERE slot_name = 'debezium';
EOF
lab_expect_contains "slot caught up"

log "Exercise 10 (advanced): JDBC sink, an incompatible schema breaks the connector"
run_model connect-connect-jdbc-postgresql-sink postgres-sink-repro-000010-incompatible-schema-breaks-sink.sh
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains 'ERROR: column "quantity" is of type integer but expression is of type character varying'
lab_run playground schema history --subject orders-value
lab_expect_contains "orders-value: registered v1 (id 1, AVRO)"
lab_expect_contains "orders-value: compatibility NONE"
lab_expect_contains "orders-value: registered v2 (id 2, AVRO)"
lab_run playground schema diff --subject orders-value --from 1 --to 2
lab_expect_contains "quantity type: int → string"
lab_expect_contains "❌ BACKWARD"
cat > "$chain_file" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"price","type":"float"},{"name":"quantity_label","type":["null","string"],"default":null}]}
EOF
playground schema set-compatibility --subject orders-value --compatibility BACKWARD
lab_run playground schema check-compatibility --subject orders-value --schema @"$chain_file"
lab_expect_contains "register would refuse it (40901)" "the corrected schema refused while the bad v2 is the latest version"
playground schema delete --subject orders-value --version 2
lab_run playground schema check-compatibility --subject orders-value --schema @"$chain_file"
lab_expect_contains "register would accept it" "the corrected schema accepted once v2 is soft deleted"

log "Exercise 11 (advanced): which version of the HTTP sink brought its HTTP logs?"
lab_run bash -c "cd '$academy/connect-connect-http-sink' && CONNECTOR_TAG=1.7.13 bash http-sink-repro-000011-which-version-brought-http-logs.sh"
lab_expect_contains "🐞 REPRODUCED"
lab_expect_contains "connector 1.7.13)"
lab_run bash -c "cd '$academy/connect-connect-http-sink' && CONNECTOR_TAG=1.7.14 bash http-sink-repro-000011-which-version-brought-http-logs.sh"
lab_expect_contains "✅ NOT REPRODUCED"
lab_expect_contains "connector 1.7.14)"
lab_run playground connector-plugin changelog --connector-plugin confluentinc/kafka-connect-http --from 1.7.13 --to 1.7.14
lab_expect_contains "CC-45231"

log "✅ academy lab: the exercises behave as the page says"
