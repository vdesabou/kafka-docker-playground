#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-flink

# id of the job named insert-into_…<table> that is not finished yet
function flink_job_id () {
    playground flink list-jobs --json | jq -r --arg table "$1" '[.[] | select((.name | endswith("." + $table)) and (.state | IN("FINISHED", "CANCELED", "FAILED") | not))][0].jid // empty'
}

lab_require_plaintext
# the kafka sql connector is released for one flink minor version: pin both when FLINK_TAG is not set (same as
# flink/flink-sql-kafka), and download it with FLINK_URL instead of the interactive question of --enable-flink
if [ "$FLINK_TAG" == "latest" ]
then
    export FLINK_TAG="2.2"
fi
FLINK_KAFKA_CONNECTOR_VERSION=${FLINK_KAFKA_CONNECTOR_VERSION:-"5.0.0-2.2"}
export FLINK_URL="https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/${FLINK_KAFKA_CONNECTOR_VERSION}/flink-sql-connector-kafka-${FLINK_KAFKA_CONNECTOR_VERSION}.jar"
export ENABLE_FLINK=true
lab_start_environment

playground topic create --topic orders
playground topic create --topic orders-enriched
playground topic produce -t orders --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "order",
  "fields": [
    { "name": "id", "type": { "type": "int", "arg.properties": { "iteration": { "start": 1 } } } },
    { "name": "product", "type": { "type": "string", "arg.properties": { "options": ["laptop", "phone", "tablet"] } } },
    { "name": "quantity", "type": { "type": "int", "arg.properties": { "range": { "min": 1, "max": 10 } } } }
  ]
}
EOF

log "Step 1: a streaming job, from Kafka to Kafka"
lab_run playground flink sql << 'EOF'
CREATE TABLE orders (id INT, product STRING, quantity INT) WITH (
  'connector' = 'kafka', 'topic' = 'orders', 'properties.bootstrap.servers' = 'broker:9092',
  'properties.group.id' = 'flink-orders', 'scan.startup.mode' = 'earliest-offset', 'format' = 'json'
);
CREATE TABLE orders_enriched (id INT, product STRING, quantity INT, price DOUBLE) WITH (
  'connector' = 'kafka', 'topic' = 'orders-enriched', 'properties.bootstrap.servers' = 'broker:9092', 'format' = 'json'
);
INSERT INTO orders_enriched SELECT id, UPPER(product), quantity, quantity * 9.99 FROM orders;
EOF
lab_expect_exit 0
lab_expect_contains "🐿️ Running Flink SQL statements in sql-client container (Flink"
lab_expect_contains "[INFO] Execute statement succeeded."
lab_expect_contains "[INFO] SQL update statement has been successfully submitted to the cluster:"
lab_expect_contains "submitted, follow it with: playground flink list-jobs"
lab_run playground topic consume --topic orders-enriched --min-expected-messages 10 --timeout 120
lab_expect_exit 0

log "Step 2: a batch query, on a bounded read of the same topic"
lab_run playground flink sql << 'EOF'
SET 'execution.runtime-mode' = 'batch';
CREATE TABLE orders (id INT, product STRING, quantity INT) WITH (
  'connector' = 'kafka', 'topic' = 'orders', 'properties.bootstrap.servers' = 'broker:9092',
  'scan.startup.mode' = 'earliest-offset', 'scan.bounded.mode' = 'latest-offset', 'format' = 'json'
);
SELECT COUNT(*) AS nb_orders, SUM(quantity) AS total_quantity FROM orders;
EOF
lab_expect_exit 0
lab_expect_contains "| nb_orders | total_quantity |"
lab_expect_equals "$(grep -c -E '^\| +10 \|' <<< "$LAB_OUTPUT")" "1" "the batch query counts 10 orders"

log "Step 3: the jobs of the cluster"
lab_run playground flink list-jobs --state RUNNING
lab_expect_exit 0
lab_expect_contains "📋 Jobs of the Flink cluster (Flink"
lab_expect_contains "JOB ID STATE NAME START DURATION"
lab_expect_contains "RUNNING insert-into_default_catalog.default_database.orders_enriched"
lab_run bash -c "playground flink list-jobs --json | jq -r '.[] | \"\(.jid) \(.state) \(.name)\"'"
lab_expect_exit 0
lab_expect_contains "RUNNING insert-into_default_catalog.default_database.orders_enriched"

log "Step 4: several jobs, and cancelling them"
lab_run playground flink sql << 'EOF'
CREATE TABLE gen (id INT) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE nowhere (id INT) WITH ('connector' = 'blackhole');
INSERT INTO nowhere SELECT * FROM gen;
EOF
lab_expect_exit 0
lab_run playground flink cancel
lab_expect_exit 1
lab_expect_contains "❌ several jobs are running, choose one with --job, or cancel them all with --all:"
nowhere_job=$(flink_job_id nowhere)
lab_expect_equals "$([ -n "$nowhere_job" ] && echo found)" "found" "id of the nowhere job"
lab_run playground flink cancel --job "$nowhere_job"
lab_expect_exit 0
lab_expect_contains "🛑 Cancelling job $nowhere_job (insert-into_default_catalog.default_database.nowhere)"
lab_expect_contains "✅ Job $nowhere_job is CANCELED"
lab_run playground flink cancel
lab_expect_exit 0
lab_expect_contains "(insert-into_default_catalog.default_database.orders_enriched)" "the only job left is cancelled"
lab_expect_contains "is CANCELED"
lab_run playground flink cancel
lab_expect_exit 0
lab_expect_contains "🤷 no running job to cancel"
lab_run playground flink list-jobs --state RUNNING
lab_expect_exit 0
lab_expect_contains "🤷 no job in state RUNNING"

log "Step 5: a job that fails at runtime"
lab_run playground flink sql << 'EOF'
SET 'restart-strategy.type' = 'none';
CREATE TABLE words (s STRING) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE numbers (n INT) WITH ('connector' = 'blackhole');
INSERT INTO numbers SELECT CAST(s AS INT) FROM words;
EOF
lab_expect_exit 0
lab_expect_contains "submitted, follow it with: playground flink list-jobs"
nb_failed=0
for i in {1..30}
do
    nb_failed=$(playground flink list-jobs --json --state FAILED | jq 'length')
    if [ "$nb_failed" != "0" ]
    then
        break
    fi
    sleep 2
done
lab_expect_equals "$nb_failed" "1" "number of FAILED jobs"
lab_run playground flink list-jobs --state FAILED
lab_expect_exit 0
lab_expect_contains "FAILED insert-into_default_catalog.default_database.numbers"
lab_expect_contains "failed with:"
lab_expect_contains "🎓 full stack traces: playground container logs -c jobmanager --errors"

log "Step 6: the three classic mistakes"
lab_run playground flink sql < /dev/null
lab_expect_exit 1
lab_expect_contains "❌ no SQL statements: pass them on stdin (heredoc) or with --file"
lab_run playground flink sql << 'EOF'
CREATE TABLE customers (id INT) WITH ('connector' = 'jdbc', 'url' = 'jdbc:postgresql://postgres:5432/postgres', 'table-name' = 'customers');
SELECT * FROM customers;
EOF
lab_expect_exit 1
lab_expect_contains "[ERROR] Could not execute SQL statement."
lab_expect_contains "❌ a Flink SQL statement failed, the next statements were not run"
lab_expect_contains "the connector or format is not in the Flink image: set FLINK_URL to the jar to download"
lab_run playground flink sql --max-wait 20 << 'EOF'
CREATE TABLE gen (id INT) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
SELECT * FROM gen;
EOF
lab_expect_exit 1
lab_expect_contains "⏱️ the SQL client was stopped after 20s: a SELECT on an unbounded table never ends in streaming mode"
lab_expect_contains "its job may still run on the cluster: playground flink list-jobs --state RUNNING, then playground flink cancel"
# the collect job of the stopped SELECT may or may not still run: not asserted
lab_run playground flink cancel --all

log "✅ all the outputs of the page are as expected"
