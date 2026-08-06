#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.0.28"
then
     logwarn "minimal supported connector version is 2.0.29 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$4}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}


if [ -z "$SALESFORCE_USERNAME" ]
then
     logerror "SALESFORCE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD" ]
then
     logerror "SALESFORCE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Login with sfdx CLI"
salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
salesforce_sfdx_with_retry "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

# Remove what this test created, so repeated runs do not accumulate records in a
# shared Salesforce org. Only the exact Lead created above is matched, so a
# concurrent test's data is never touched. Registered as an EXIT trap so cleanup
# also happens when an assertion below fails.
cleanup_salesforce_test_data() {
  set +e
  log "🧹 Cleaning up: Lead $LEAD_FIRSTNAME $LEAD_LASTNAME"
  salesforce_sfdx_with_retry --stdin "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF
Database.delete([SELECT Id FROM Lead WHERE FirstName = '$LEAD_FIRSTNAME' AND LastName = '$LEAD_LASTNAME'], false);
EOF
  set -e
}
trap cleanup_salesforce_test_data EXIT

# Wait for the connector's task to reach RUNNING, restarting it if it died with
# INVALID_SESSION_ID.
#
# The Bulk API connectors authenticate with the username-password SOAP grant. Connector
# validation opens its own PartnerConnection and ends it with a SOAP logout(), and
# Salesforce reuses one session across identical logins by the same user - so validation
# can tear down the session the task is holding. The task then fails its very first
# describeSObject with INVALID_SESSION_ID ("Session not found, missing session hash")
# within seconds of starting, and Connect does not retry a task that threw from start().
#
# Restarting the task re-authenticates without re-running validation, which is also the
# remedy Salesforce documents for a session invalidated by a concurrent logout. Only
# INVALID_SESSION_ID is retried: any other task failure fails the test immediately, so a
# genuine regression is still caught.
restart_task_on_invalid_session() {
  local connector="$1"
  local max_restarts="${2:-2}"
  local restarts=0
  local checks=0
  local task_status state trace

  while [ "$checks" -lt 12 ]; do
    sleep 10
    checks=$((checks + 1))
    task_status=$(curl -s "http://localhost:8083/connectors/${connector}/status")
    state=$(echo "$task_status" | jq -r '.tasks[0].state // "MISSING"')

    case "$state" in
      RUNNING)
        if [ "$restarts" -gt 0 ]; then
          log "✅ $connector task reached RUNNING after $restarts restart(s)"
        fi
        return 0
        ;;
      FAILED)
        trace=$(echo "$task_status" | jq -r '.tasks[0].trace // ""')
        if ! echo "$trace" | grep -q "INVALID_SESSION_ID"; then
          logerror "$connector task FAILED, and not with INVALID_SESSION_ID:"
          echo "$trace" | head -20
          return 1
        fi
        if [ "$restarts" -ge "$max_restarts" ]; then
          logerror "$connector still hitting INVALID_SESSION_ID after $restarts restart(s)"
          return 1
        fi
        restarts=$((restarts + 1))
        logwarn "⚠️ $connector hit INVALID_SESSION_ID, restarting task ($restarts/$max_restarts)"
        curl -s -X POST "http://localhost:8083/connectors/${connector}/tasks/0/restart" > /dev/null
        ;;
      *)
        # UNASSIGNED or not yet reported while the task is still coming up.
        ;;
    esac
  done

  logerror "$connector task never reached RUNNING (last state: $state)"
  return 1
}

log "Creating Salesforce Bulk API Source connector"
salesforce_create_connector_with_retry salesforce-bulkapi-source << EOF
{
     "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSourceConnector",
     "kafka.topic": "sfdc-bulkapi-leads",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.object" : "Lead",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.username" : "$SALESFORCE_USERNAME",
     "salesforce.password" : "$SALESFORCE_PASSWORD",
     "salesforce.password.token" : "$SALESFORCE_SECURITY_TOKEN",
     "connection.max.message.size": "10048576",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

restart_task_on_invalid_session salesforce-bulkapi-source

# 180s, not 60s: the Bulk API query job runs asynchronously on a Salesforce-side
# queue, so how long it takes to complete is not under this test's control and
# varies from seconds to minutes.
log "Verify we have received the data in sfdc-bulkapi-leads topic"
playground topic consume --topic sfdc-bulkapi-leads --min-expected-messages 1 --timeout 180