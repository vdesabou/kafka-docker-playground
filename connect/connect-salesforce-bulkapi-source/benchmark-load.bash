#!/bin/bash
# load for 'playground connector benchmark': Leads created in Salesforce with one Bulk API job, then picked up by the
# Bulk API source connector of the example (a real-life "your own load", see the documentation)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

# --records <n> --mode preload|stream --shape bulk|small-txn|update [--check]
benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"

# --check: called before the connector is paused, refuse what this load cannot do
if [ -n "$BENCHMARK_LOAD_CHECK" ]
then
  if [ "$BENCHMARK_LOAD_SHAPE" != "bulk" ] || [ "$BENCHMARK_LOAD_MODE" != "preload" ]
  then
    # a stream of jobs would fill the org: a developer org holds about 2500 Leads (5 MB of data storage)
    logerror "❌ this load creates the Leads with one Bulk API job: --mode drain --shape bulk only"
    exit 1
  fi
  exit 0
fi

# the Salesforce user of the connector: the connect REST API shows it (only the passwords are masked), and the sfdx-cli
# container of the example is already logged in with it
username=$(benchmark_connector_config_value salesforce.username)
if [ -z "$username" ]
then
  logerror "❌ no salesforce.username in the config of the connector"
  exit 1
fi
function sfdx () {
  playground --output-level ERROR container exec --container sfdx-cli --shell sh --command "sfdx $1"
}

# the Leads of the previous runs first: the org would fill up (the source connector does not see deletes)
sfdx "force:data:soql:query --target-org '$username' -q \"SELECT Id FROM Lead WHERE Company = 'playground-benchmark'\" -r csv > /tmp/benchmark-leads-old.csv"
previous=$(playground --output-level ERROR container exec --container sfdx-cli --shell sh --command "grep -c . /tmp/benchmark-leads-old.csv" 2> /dev/null | tr -dc '0-9')
if [ "${previous:-0}" -gt 1 ]
then
  log "🧹 deleting the $((previous - 1)) Leads of the previous benchmark runs"
  sfdx "force:data:bulk:delete --target-org '$username' -s Lead -f /tmp/benchmark-leads-old.csv -w 30" > /dev/null
fi

# <records> Leads in one Bulk API job: an upsert on Id with an empty Id inserts every row
run="$(date +%s)"
awk -v n="$records" -v run="$run" 'BEGIN {
  print "Id,FirstName,LastName,Company"
  for (i = 1; i <= n; i++) printf ",Lead%d,benchmark-%s-%d,playground-benchmark\n", i, run, i
}' | playground --output-level ERROR container exec --container sfdx-cli --shell sh --command "cat > /tmp/benchmark-leads.csv"
log "📥 creating $records Leads in Salesforce with one Bulk API job"
result=$(sfdx "force:data:bulk:upsert --target-org '$username' -s Lead -f /tmp/benchmark-leads.csv -i Id -w 30 --json")
failed=$(echo "$result" | jq '[.result[]? | (.numberRecordsFailed // "0" | tonumber)] | add // 0' 2> /dev/null)
if [ "${failed:-0}" -gt 0 ]
then
  logerror "❌ $failed Leads could not be created (a developer org holds about 2500 Leads: reduce --nb-records)"
  echo "$result" | jq -r '[.result[]? | .stateMessage? // empty] | unique | .[]' 2> /dev/null | head -5
  exit 1
fi

# one record per Lead in the topic of the connector
echo "BENCHMARK_RECORDS=$records"
