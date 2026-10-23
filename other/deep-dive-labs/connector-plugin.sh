#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-connector-plugin (no environment needed)
lab_require_plaintext
playground_cli="${DIR}/../../scripts/cli/playground"

log "Step 1: versions, and the cache"
lab_run playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 3
lab_expect_exit 0
lab_expect_contains "💯 Listing last 3 versions for connector plugin confluentinc/kafka-connect-jdbc"
lab_expect_equals "$(grep -c "🔢 v" <<< "$LAB_OUTPUT")" "3" "number of versions listed"
lab_expect_contains "🌐 documentation: https://docs.confluent.io/kafka-connect-jdbc/current/"
if [ ! -f /tmp/version_confluentinc_kafka-connect-jdbc ]
then
    logerror "❌ cache file /tmp/version_confluentinc_kafka-connect-jdbc not found"
    exit 1
fi
log "✅ cache file /tmp/version_confluentinc_kafka-connect-jdbc"

log "Step 2: a config key, everywhere then for one connector"
lab_run playground connector-plugin config-key --key flush.size
lab_expect_contains "connector(s) have key flush.size, use --connector-class to see the details of one"
lab_expect_contains "io.confluent.connect.s3.S3SinkConnector"
lab_run playground connector-plugin config-key --key batch.size -c io.confluent.connect.jdbc.JdbcSinkConnector
lab_expect_contains "🔑 batch.size in io.confluent.connect.jdbc.JdbcSinkConnector (group: Writes)"
lab_expect_contains "- Type: INT"
lab_expect_contains "- Default: 3000"

log "Step 3: framework keys and typos"
lab_run playground connector-plugin config-key --key errors.tolerance -c JdbcSinkConnector
lab_expect_exit 0
lab_expect_contains "🧩 errors.tolerance is a Kafka Connect framework key, common to every connector"
lab_run playground connector-plugin config-key --key batch.sise -c JdbcSinkConnector
lab_expect_exit 1
lab_expect_contains "🤷 key batch.sise not found for connector JdbcSinkConnector"

log "Step 4: the code at the customer's version, and what changed"
lab_run playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url
lab_expect_exit 0
lab_expect_contains "https://github.com/confluentinc/kafka-connect-jdbc/tree/v10.8.4"
lab_run playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --connector-tag 10.9.9 --only-show-url
lab_expect_contains "comparison mode will be opened with versions v10.8.4 and v10.9.9"
lab_expect_contains "https://github.com/confluentinc/kafka-connect-jdbc/compare/v10.8.4...v10.9.9"
lab_run bash -c "$playground_cli connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --checkout-only < /dev/null | tail -1"
lab_expect_contains "/tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.8.4"
lab_run grep -rn "BATCH_SIZE_DEFAULT = " /tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.8.4/src/main/java
lab_expect_contains "JdbcSinkConfig.java"
lab_expect_contains "private static final int BATCH_SIZE_DEFAULT = 3000;"

log "Step 5: which jar has a class (Docker)"
lab_run playground connector-plugin search-jar -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --class PostgreSqlDatabaseDialect
lab_expect_contains "kafka-connect-jdbc-10.8.4.jar"
lab_expect_contains "👉 method signatures from ./kafka-connect-jdbc-10.8.4.jar jar for class io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect"

# step 6 (fully managed connector) needs GH_TOKEN and the Confluent VPN: not replayed

log "✅ all the outputs of the page are as expected"
