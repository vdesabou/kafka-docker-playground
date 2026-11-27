#!/bin/bash
# The HTML reports of the commands that need a real run (a running connector, a CI job, a benchmark, a scan), built from
# the synthetic inputs shipped in the samples/ folder of each tool, with the generator the command calls:
#
#   connector-diagnose.html  playground connector diagnose          tools/connector-diagnose/samples/jdbc_sink_failed_task
#   ci-result.html           playground get-ci-result --logs        tools/log-analyzer/samples/ci-result
#   benchmark.html           playground connector benchmark         tools/benchmark-report/samples/jdbc_sink_10.8.4_vs_10.9.9
#   cve-scan.html            playground connector-plugin cve-scan   tools/connector-plugin-jars/samples/jdbc_10.7.4_vs_10.9.9
#   connector-diff.html      playground connector diff              tools/connector-diff/samples/jdbc_sink_vs_other_config
#   dlq.html                 playground topic dlq inspect           tools/dlq-tool/samples/jdbc_sink_dlq
#   smt-test.html            playground connector smt test          tools/smt-tester/samples/jdbc_sink_chain
#
# The reports gallery of the website (scripts/generate-reports-gallery.sh of vdesabou/kafka-docker-playground-docs, run by
# .github/workflows/update-reports-gallery.yml) calls it, so these reports follow every change of the report code like the
# reports of the analyze samples, instead of staying as they were on the day of a hand run.
#
#   tools/report-common/real_run_samples.sh <output folder>
#
# Standard library python3 and awk only: no Docker, no network, no playground environment.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:?usage: $0 <output folder>}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# the log digest of the CLI (summarize_log_errors of scripts/cli/src/lib/cli_function.sh), as its tests run it
# (tools/log-analyzer/test_digest_awk.sh): it writes the records file the reports read
export PLAYGROUND_AWK=awk
{ sed -n '/^function log_awk/,/^}/p' "$root/scripts/cli/src/lib/cli_function.sh"
  sed -n '/^function summarize_log_errors/,/^}/p' "$root/scripts/cli/src/lib/cli_function.sh"; } > "$tmp/digest.sh"
# shellcheck disable=SC1091
source "$tmp/digest.sh"

# 🩺 connector diagnose: the folder written by scripts/cli/src/commands/connector/diagnose.sh, its errors.records from the
# connect log of the sample (playground container logs --errors in a real run)
sample="$root/tools/connector-diagnose/samples/jdbc_sink_failed_task"
cp -R "$sample" "$tmp/diagnose"
PG_LOG_DIGEST_RECORDS_FILE="$tmp/diagnose/errors.records" PG_LOG_DIGEST_LABEL="connect" \
    summarize_log_errors 40 < "$sample/connect.log" > /dev/null
python3 -I "$root/tools/connector-diagnose/diagnose_report.py" --connector-dir "$tmp/diagnose" \
    --html-out "$out/connector-diagnose.html"

# 🤖 get-ci-result --logs: the section of the failed script in the CI job, its last lines before the failure and its digest
# (the same commands as scripts/cli/src/commands/get-ci-result.sh)
section="$root/tools/log-analyzer/samples/ci-result/section.log"
script="postgres-sink.sh"
test="connect/connect-jdbc-postgresql-sink"
awk '/RESULT: FAILURE for .* \(took/ { exit } { print }' "$section" | tail -25 > "$tmp/section.tail"
: > "$tmp/ci.records"
grep -v -E "RESULT: FAILURE|has failed after [0-9]+ attempts|^playground container display-error-all$|🔥 #+$" "$section" \
    | PG_LOG_DIGEST_RECORDS_FILE="$tmp/ci.records" PG_LOG_DIGEST_LABEL="$script" summarize_log_errors 40 > /dev/null
python3 -I "$root/tools/log-analyzer/log_report.py" --records "$tmp/ci.records" --html-out "$out/ci-result.html" \
    --title "$test (CP 8.4.1 🚀 plaintext)" --heading "🤖 CI failure" --unit script \
    --command "playground get-ci-result --test $test --logs" \
    --link "🐛 the 🔥 issues of the CI" "https://github.com/vdesabou/kafka-docker-playground/issues?q=is%3Aissue+is%3Aopen+%F0%9F%94%A5" \
    --link "🔗 job of the nightly run" "https://github.com/vdesabou/kafka-docker-playground/actions/workflows/ci.yml" \
    --section "🔥 $script: last lines before the failure" "$tmp/section.tail"

# 📊 connector benchmark --connector-tag 10.8.4 --connector-tag 10.9.9: two runs per version (the samples_csv of the last
# run is relative to the root of the repository)
bench="tools/benchmark-report/samples/jdbc_sink_10.8.4_vs_10.9.9"
(cd "$root" && python3 -I tools/benchmark-report/benchmark_report.py \
    --runs "$bench/run1-10.8.4.json" "$bench/run2-10.8.4.json" "$bench/run3-10.9.9.json" "$bench/run4-10.9.9.json" \
    --output "$out/benchmark.html" > /dev/null)

# 🛡️ connector-plugin cve-scan -c confluentinc/kafka-connect-jdbc --connector-tag 10.7.4 --compare-with 10.9.9: the grype
# scans of both versions and the release notes between them
cve="$root/tools/connector-plugin-jars/samples/jdbc_10.7.4_vs_10.9.9"
python3 -I "$root/tools/connector-plugin-jars/cve_scan.py" --scan "$cve/grype-10.7.4.json" --compare-scan "$cve/grype-10.9.9.json" \
    --label 10.7.4 --compare-label 10.9.9 --plugin confluentinc/kafka-connect-jdbc --changelog "$cve/changelog.json" \
    --html-out "$out/cve-scan.html" > /dev/null

# 🔀 connector diff --connector jdbc-sink --with other-jdbc-sink.json: the documentation of each key from the configuration
# reference of the JDBC sink example
diff="$root/tools/connector-diff/samples/jdbc_sink_vs_other_config"
python3 -I "$root/tools/connector-diff/diff_report.py" --diff "$diff/diff.json" --a jdbc-sink --b other-jdbc-sink.json \
    --connector-class io.confluent.connect.jdbc.JdbcSinkConnector \
    --reference "$root/connect/connect-jdbc-postgresql-sink/config-io.confluent.connect.jdbc.JdbcSinkConnector.txt" \
    --html-out "$out/connector-diff.html"

# ☠️ topic dlq inspect --topic dlq-jdbc-sink: the groups and records DlqTool decoded, its summary passed as JSON text
dlq="$root/tools/dlq-tool/samples/jdbc_sink_dlq"
python3 -I "$root/tools/dlq-tool/dlq_report.py" --groups "$dlq/groups.json" --records "$dlq/records.json" \
    --summary "$(cat "$dlq/summary.json")" --topic dlq-jdbc-sink --html-out "$out/dlq.html"

# 🧪 connector smt test: a record through a chain of four transforms (one skipped by its predicate)
python3 -I "$root/tools/smt-tester/smt_report.py" --result "$root/tools/smt-tester/samples/jdbc_sink_chain/result.json" \
    --output "$out/smt-test.html" --title "SMT test of jdbc-sink"

ls "$out"/*.html
