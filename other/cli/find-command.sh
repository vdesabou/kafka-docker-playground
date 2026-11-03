#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# ranking of 'playground find-command': each question must list the expected command in its first N hits.
# No environment needed. When a row of docs/which-command.md or a recipe of a deep dive changes the ranking on
# purpose, update the expectation here.
log "🧭 Checking the ranking of playground find-command"

# question|expected command (without "playground ")|in the first N hits
cases=(
    "why is my connector not working|connector diagnose|1"
    "memory issue with connector|analyze heap-dump|2"
    "memory issue with connector|analyze gc-logs|2"
    "OutOfMemoryError|analyze heap-dump|1"
    "connector stuck high cpu|analyze thread-dump|1"
    "customer support bundle cfk|analyze logs|1"
    "which version fixes this CVE|connector-plugin cve-scan|1"
    "docker logs|container logs|1"
    "who deleted the schema|schema history|1"
    "slow network latency|debug degrade-traffic|1"
    "dead letter queue|topic dlq inspect|1"
    "read_committed consumer stuck|broker transactions|1"
    "under replicated partitions|broker health|1"
    "oracle xstream report|analyze oracle-xstream-report|1"
    "which jackson version|connector-plugin dependencies|1"
    "strimzi KafkaConnector yaml|connector create-or-update|1"
    "sleep waiting connector running|connector create-or-update|1"
    "produce avro records with a schema|topic produce|1"
    "connector is slow|connector benchmark|1"
    "which task does all the work|connector tasks|1"
)

failed=0
for c in "${cases[@]}"
do
    IFS='|' read -r question expected top <<< "$c"
    hits=$(playground find-command "$question" --json --limit "$top" 2>/dev/null | jq -r '.[].command' || true)
    if grep -qx "playground $expected" <<< "$hits"
    then
        log "✅ \"$question\" → playground $expected"
    else
        logerror "❌ \"$question\": expected playground $expected in the first $top hit(s), got: $(echo $hits | tr '\n' ',')"
        failed=1
    fi
done

if playground find-command "zzqx" --json > /dev/null 2>&1
then
    logerror "❌ a query without any match must exit 1"
    failed=1
fi

if [ $failed -ne 0 ]
then
    exit 1
fi
log "✅ find-command ranking as expected"
