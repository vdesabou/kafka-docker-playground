#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-connector-plugin (no environment needed)
lab_require_plaintext
playground_cli="${DIR}/../../scripts/cli/playground"

log "Step 1: versions, the cache, and what changed"
lab_run playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 3
lab_expect_exit 0
lab_expect_contains "💯 Listing last 3 versions for connector plugin confluentinc/kafka-connect-jdbc"
lab_expect_equals "$(grep -c "🔢 v" <<< "$LAB_OUTPUT")" "3" "number of versions listed"
lab_expect_contains "🌐 documentation: https://docs.confluent.io/kafka-connect-jdbc/current/"
if [ ! -f /tmp/version_confluentinc_kafka-connect-jdbc.json ]
then
    logerror "❌ cache file /tmp/version_confluentinc_kafka-connect-jdbc.json not found"
    exit 1
fi
log "✅ cache file /tmp/version_confluentinc_kafka-connect-jdbc.json"
lab_run playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --from 10.9.5 --last 2
lab_expect_exit 0
lab_expect_contains "📌 10.9.5 is"
lab_expect_contains "version(s) behind the latest"
lab_expect_equals "$(grep -c "🔢 v" <<< "$LAB_OUTPUT")" "2" "number of versions listed"
lab_expect_not_contains "v10.9.5 -"
lab_run playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --latest
lab_expect_exit 0
lab_expect_equals "$(grep -cE '^[0-9][0-9A-Za-z.-]*$' <<< "$LAB_OUTPUT")" "1" "--latest prints only the version"
lab_run playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 2 --json
lab_expect_exit 0
lab_expect_equals "$(jq '.versions | length' <<< "$LAB_OUTPUT")" "2" "number of versions in the JSON"
lab_expect_equals "$(jq -r '.versions[-1].version == .latest' <<< "$LAB_OUTPUT")" "true" "last version of the JSON is latest"
lab_run playground connector-plugin changelog -c confluentinc/kafka-connect-jdbc --from 10.9.6 --to 10.9.8
lab_expect_exit 0
lab_expect_contains "📜 Release notes of confluentinc/kafka-connect-jdbc after 10.9.6 up to 10.9.8: 2 version(s)"
lab_expect_contains "🔢 v10.9.8 - 📅 release date: 2026-09-16"
lab_expect_contains "PR-1691 - Fix high CPU: JDBC source task busy-spins while waiting for table list"
lab_expect_contains "🌐 changelog: https://docs.confluent.io/kafka-connectors/jdbc/10.9/changelog.html"
lab_expect_not_contains "v10.9.6 -"
lab_run playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 3 --with-changelog
lab_expect_exit 0
lab_expect_equals "$(grep -c "🔢 v" <<< "$LAB_OUTPUT")" "3" "number of versions listed"
lab_expect_contains "   • "
lab_expect_contains "📜 changelog: https://docs.confluent.io/kafka-connectors/jdbc/"
lab_run playground connector-plugin display-last-updated --days 365 --vendor confluentinc --json
lab_expect_exit 0
lab_expect_equals "$(jq 'length > 0' <<< "$LAB_OUTPUT")" "true" "confluentinc plugins released in the last year"
lab_expect_equals "$(jq '[.[].release_date] == ([.[].release_date] | sort | reverse)' <<< "$LAB_OUTPUT")" "true" "newest first"
lab_expect_equals "$(jq 'all(.connector_plugin | startswith("confluentinc/"))' <<< "$LAB_OUTPUT")" "true" "--vendor filter"

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
lab_expect_contains "🔎 1 class(es) named PostgreSqlDatabaseDialect in the jars of confluentinc/kafka-connect-jdbc:10.8.4"
lab_expect_contains "👉 io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect in kafka-connect-jdbc-10.8.4.jar"
lab_expect_contains "public class io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect extends io.confluent.connect.jdbc.dialect.GenericDatabaseDialect"
lab_run playground connector-plugin search-jar -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --with-worker
lab_expect_exit 0
lab_expect_contains "slf4j-api-1.7.36.jar"

# step 6 (fully managed connector) needs GH_TOKEN and the Confluent VPN: not replayed

log "✅ all the outputs of the page are as expected"
