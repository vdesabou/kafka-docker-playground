#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of the intermediate (⭐⭐) exercises of https://kafka-docker-playground.io/#/academy: runs their reproduction models
# (academy/) and asserts the issue each exercise is about, then the fix the page gives. The S3 exercise (AWS account) is
# in academy.sh. Its own lab, so that each one stays well under the 60 minutes CI timeout of a script
lab_require_plaintext
academy="${DIR}/../../academy"

function run_model () {
    lab_run bash -c "cd '$academy/$1' && bash '$2'"
}

# `connector offsets alter` opens the offsets in the editor of `playground config get editor` and waits for it: a
# scripted editor writes the content of $lab_tmp/offsets.json instead, and the editor is restored at the end
lab_tmp=$(mktemp -d)
prev_editor=$(playground config get editor 2>/dev/null | tail -1)
cat > "$lab_tmp/editor.sh" << EOF
#!/bin/bash
cp "$lab_tmp/offsets.json" "\$1"
EOF
chmod +x "$lab_tmp/editor.sh"
playground config set editor "$lab_tmp/editor.sh"
trap 'playground topic produce --topic orders --stop > /dev/null 2>&1 || true; playground config set editor "${prev_editor:-code}"; rm -rf "$lab_tmp"' EXIT

# wait_for_output <max seconds> <text> <command...>: runs the command every 15 seconds until its output contains <text>
function wait_for_output () {
    local max_wait="$1"
    local text="$2"
    shift 2
    local start=$SECONDS
    while true
    do
        lab_run "$@"
        if grep -qF -- "$(lab_squeeze "$text")" <<< "$(lab_squeeze "$LAB_OUTPUT")"
        then
            return 0
        fi
        if [ $((SECONDS - start)) -ge "$max_wait" ]
        then
            logerror "❌ '$text' not found after $max_wait seconds"
            exit 1
        fi
        sleep 15
    done
}

log "Exercise 12 (intermediate): JDBC source, the updated rows never reach the topic"
run_model connect-connect-jdbc-mysql-source mysql-repro-000012-jdbc-source-misses-updates.sh
lab_expect_contains "it contains 4 messages"
lab_expect_contains '"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"club_status":{"string":"bronze"}'
lab_expect_contains '"id":4,"first_name":{"string":"Hashim"}'
lab_expect_not_contains '"club_status":{"string":"gold"}' "the update is not in the topic"
lab_run playground db sql --database mydb << 'EOF'
SELECT id, first_name, club_status, update_ts FROM CUSTOMERS WHERE id = 1;
EOF
lab_expect_contains "| 1 | Rica | gold |"
# a source connector commits its offsets every 60 seconds
wait_for_output 120 '"incrementing": 4' playground connector offsets get --connector mysql-source
lab_expect_contains '"table": "mydb.CUSTOMERS"'
playground connector create-or-update --connector mysql-source << EOF
{
     "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max":"1",
     "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false&allowPublicKeyRetrieval=true",
     "table.whitelist":"CUSTOMERS",
     "mode":"timestamp+incrementing",
     "timestamp.column.name":"update_ts",
     "incrementing.column.name":"id",
     "poll.interval.ms":"1000",
     "topic.prefix":"mysql-",
     "value.converter":"io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081"
}
EOF
playground topic wait-for-records --topic mysql-CUSTOMERS --min-expected-messages 8 --max-wait 60
lab_run playground topic consume --topic mysql-CUSTOMERS
lab_expect_contains "it contains 8 messages" "the switch sends the whole table again"
lab_expect_contains '|Offset:6|'
lab_expect_contains '"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"club_status":{"string":"gold"}'
playground db sql --database mydb << 'EOF'
UPDATE CUSTOMERS SET club_status = 'platinum' WHERE id = 3;
EOF
playground topic wait-for-records --topic mysql-CUSTOMERS --min-expected-messages 9 --max-wait 60
lab_run playground topic consume --topic mysql-CUSTOMERS
lab_expect_contains '"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"club_status":{"string":"platinum"}'
wait_for_output 120 '"timestamp_nanos"' playground connector offsets get --connector mysql-source
lab_expect_contains '"incrementing": 3'

log "Exercise 13 (intermediate): HTTP sink, tasks.max is 4 but only one task works"
run_model connect-connect-http-sink http-sink-repro-000013-tasks-max-one-task-works.sh
lab_expect_contains "consumer lag for 🌎onprem connector http-sink is"
lab_run playground connector tasks --connector http-sink
lab_expect_contains "tasks.max=4, 4 task(s))"
lab_expect_contains "orders-0"
lab_expect_contains "1 🟢 RUNNING connect:8083 - (no partition assigned)"
lab_expect_contains "💤 3 task(s) without partition: tasks.max is higher than the number of partitions of the topics, or the consumer group is rebalancing"
lab_run playground topic describe --topic orders
lab_expect_contains "PartitionCount: 1"
# the tip of Step 2: connector lint finds it from the config and the topic
lab_run playground connector lint --connector http-sink
lab_expect_contains "🟡 LOW tasks.max = 4"
lab_expect_contains "why: 4 tasks for 1 partition(s): 3 task(s) stay idle"
lab_expect_contains "fix: set tasks.max=1 or add partitions (playground topic add-partitions)"
lab_run playground topic add-partitions --topic orders --nb-partitions 4
lab_expect_contains "➕ Adding partitions to topic orders: 1 → 4"
lab_expect_contains "✅ topic orders has 4 partitions"
lab_expect_contains "⚠️ records with a key: hash(key) % 4 now decides their partition, new records of a key can land in another partition than the older ones"
lab_run playground topic add-partitions --topic orders --nb-partitions 2
lab_expect_contains "❌ topic orders already has 4 partition(s): a topic can only grow (Kafka never removes partitions), give more than 4"
# the metadata refresh (metadata.max.age.ms, 5 minutes), then a rebalance that waits for the put() of task 0
wait_for_output 720 "3 🟢 RUNNING connect:8083 orders-3" playground connector tasks --connector http-sink
lab_expect_contains "0 🟢 RUNNING connect:8083 orders-0"
lab_run playground topic get-offsets --topic orders
lab_expect_contains "PARTITION EARLIEST LATEST RECORDS"
lab_expect_not_contains "3 0 0 0" "new orders land in partition 3"
lab_run playground connector create-or-update --connector http-sink << EOF
{
     "topics": "orders",
     "tasks.max": "4",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":"false",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "reporter.result.topic.value.format": "string",
     "http.api.url": "http://httpserver:9006",
     "request.body.format" : "json",
     "headers": "Content-Type: application/json",
     "batch.max.size": "50"
}
EOF
lab_expect_contains "~ batch.max.size: 1 → 50"
lab_expect_contains "is RUNNING (4 task(s))"
playground topic produce --topic orders --stop

log "Exercise 14 (intermediate): HTTP sink, the API answers 400 and errors.tolerance doesn't help"
run_model connect-connect-http-sink http-sink-repro-000014-http-sink-400-and-dlq.sh
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Status code : 400, Reason Phrase : Bad Request"
lab_run playground tools http-server requests
lab_expect_contains "📥 4 request(s) received since the start or the last reset"
lab_expect_contains '#4 '
lab_expect_contains '"id":1,'
lab_expect_not_contains '"id":2,' "records 2 and 3 never sent"
lab_run playground topic dlq inspect --topic dlq --no-open
lab_expect_contains "✅ dead letter queue dlq is empty"
lab_run playground topic consume --topic error-responses
lab_expect_contains "it contains 1 messages"
lab_expect_contains 'response_content:{"error":"email: must be a company address"},status_code:400'
playground tools http-server reset
playground tools http-server set-response --status-code 400
playground tools http-server set-response << 'EOF'
{"error":"email: must be a company address"}
EOF
playground connector create-or-update --connector http-sink << EOF
{
     "topics": "http-messages",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":"false",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "reporter.result.topic.value.format": "string",
     "http.api.url": "http://httpserver:9006",
     "request.body.format" : "json",
     "headers": "Content-Type: application/json",
     "max.retries": "3",
     "retry.backoff.ms": "1000",
     "errors.tolerance": "all",
     "errors.deadletterqueue.topic.name": "dlq",
     "errors.deadletterqueue.topic.replication.factor": "1",
     "errors.deadletterqueue.context.headers.enable": "true",
     "retry.on.status.codes": "429,500-",
     "behavior.on.error": "log"
}
EOF
playground connector restart --connector http-sink
sleep 15
lab_run playground connector status --connector http-sink
lab_expect_contains "0:🟢 RUNNING"
lab_run playground tools http-server requests
lab_expect_contains "📥 3 request(s) received since the start or the last reset"
lab_expect_contains '"id":3,'
lab_run playground topic consume --topic error-responses
lab_expect_contains "it contains 4 messages"
lab_expect_contains "input_record_offset:2,"
playground tools http-server reset
playground tools http-server set-response --status-code 200
lab_run playground connector offsets reset --connector http-sink
lab_expect_contains "have been reset successfully"
sleep 15
lab_run playground tools http-server requests
lab_expect_contains "📥 3 request(s) received since the start or the last reset"
lab_expect_contains "POST / → 200"
lab_run playground topic consume --topic success-responses
lab_expect_contains "it contains 3 messages"

log "Exercise 15 (intermediate): renamed sink connector writes every row again"
run_model connect-connect-jdbc-postgresql-sink postgres-sink-repro-000015-renamed-connector-rereads-topic.sh
lab_expect_contains " 20 | 10"
lab_run playground consumer-group list
lab_expect_contains "connect-sink-1"
lab_expect_contains "connect-postgres-orders-sink"
lab_run playground consumer-group describe --group connect-sink-1
lab_expect_contains "Consumer group 'connect-sink-1' has no active members."
lab_expect_contains "connect-sink-1 orders 0 10 10 0"
playground connector delete --connector postgres-orders-sink
playground connector create-or-update --connector orders-sink --initial-state STOPPED << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
EOF
echo '{"offsets": [{"partition": {"kafka_topic": "orders", "kafka_partition": 0}, "offset": {"kafka_offset": 10}}]}' > "$lab_tmp/offsets.json"
# the editor is never opened on CI (GITHUB_RUN_NUMBER set): clear it for this command, so that the scripted editor runs
GITHUB_RUN_NUMBER="" lab_run playground connector offsets alter --connector orders-sink
lab_expect_contains '⚠️ connector orders-sink has no offset yet: write each entry in full, for example'
lab_expect_contains 'sink: {"offsets": [{"partition": {"kafka_topic": "orders", "kafka_partition": 0}, "offset": {"kafka_offset": 10}}]}'
lab_expect_contains "have been altered successfully"
lab_expect_contains "🛑 connector orders-sink was STOPPED before the change: left STOPPED (playground connector resume --connector orders-sink to start it)"
lab_run playground connector status --connector orders-sink
lab_expect_contains "orders-sink 🛑 STOPPED"
playground connector resume --connector orders-sink
playground topic produce -t orders --nb-messages 5 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "int"},
    {"name": "price", "type": "float"}
  ]
}
EOF
playground db wait-for-rows --table orders --min-expected-rows 25
sleep 10
lab_run playground db sql << 'EOF'
SELECT count(*) AS nb_rows FROM orders;
EOF
lab_expect_contains " 25" "20 + 5: nothing read again"

log "Exercise 16 (intermediate): S3 sink, duplicated records in the bucket after a worker crash"
run_model connect-connect-minio-s3-sink s3-sink-repro-000016-s3-sink-duplicates-after-worker-crash.sh
lab_expect_contains "🪣 6 object(s)"
lab_run playground storage ls --connector minio-sink
lab_expect_contains "orders-0 6"
lab_expect_contains "🪣 6 object(s)"
lab_run playground storage cat --connector minio-sink --summary --max-objects 0
lab_expect_contains "📄 reading 6 object(s)"
lab_expect_contains "🔁 3 overlap(s)"
lab_expect_contains "offsets 0-2 are in two objects"
lab_expect_contains "offsets 3-5 are in two objects"
lab_expect_contains "offsets 6-8 are in two objects"
lab_expect_contains "📦 18 record(s) in 6 object(s)"
lab_run playground connector reconcile --connector minio-sink
lab_expect_contains "📥 topic orders 9 record(s)"
lab_expect_contains "18 record(s)"
lab_expect_contains "❌ Duplicated: 9"
lab_expect_contains '"product1", quantity="1": 2 times in the bucket'
lab_expect_contains "❌ duplicated: the same record is there several times"
[ "$LAB_EXIT" -eq 1 ] || { logerror "❌ connector reconcile should exit with 1, got $LAB_EXIT"; exit 1; }

log "Exercise 16, Step 4: timestamp.extractor=Record, the same crash"
playground connector delete --connector minio-sink
playground connector create-or-update --connector minio-sink-fixed << 'END_OF_CONFIG'
{
     "connector.class": "io.confluent.connect.s3.S3SinkConnector",
     "tasks.max": "1",
     "topics": "orders",
     "topics.dir": "topics-fixed",
     "s3.bucket.name": "mybucket",
     "s3.part.size": 5242880,
     "store.url": "http://minio:9000",
     "flush.size": "3",
     "storage.class": "io.confluent.connect.s3.storage.S3Storage",
     "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
     "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
     "partition.duration.ms": "10000",
     "path.format": "'date'=YYYY-MM-dd/'time'=HH-mm-ss",
     "locale": "en-US",
     "timezone": "UTC",
     "timestamp.extractor": "Record",
     "schema.compatibility": "NONE"
}
END_OF_CONFIG
playground storage wait-for-objects --connector minio-sink-fixed --min-expected-objects 3
playground container kill --container connect
playground container restart --container connect
playground container wait-for-connect-rest-api-ready
# the records are read again once the member of the killed worker has timed out, and their offsets committed after
wait_for_output 300 "lag: 0" playground connector show-lag --connector minio-sink-fixed --once
lab_run playground storage cat --connector minio-sink-fixed --summary --max-objects 0
lab_expect_contains "✅ contiguous"
lab_expect_contains "📦 9 record(s) in 3 object(s)"
lab_run playground connector reconcile --connector minio-sink-fixed
lab_expect_contains "✅ 9 matching"
lab_expect_contains "✅ complete: every record is on the other side, with the same values"

log "✅ academy intermediate lab: the exercises behave as the page says"
