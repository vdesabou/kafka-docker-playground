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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

log "Login with sfdx CLI"
salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
salesforce_sfdx_with_retry "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

# Remove what this test created, so repeated runs do not accumulate records in a shared
# Salesforce org. Only the exact records created above are matched, so a concurrent test's
# data is never touched. An EXIT trap so cleanup also happens when an assertion fails.
cleanup_salesforce_test_data() {
  set +e
  # Cleanup gets its own retry allowance: the test body may already have spent the shared
  # budget, and with two orgs the first delete could otherwise leave the second with a
  # single attempt.
  SALESFORCE_CREATE_RETRIES_USED=0
  local cleanup_failed=0
  salesforce_sfdx_relogin """"
  log "🧹 Cleaning up: Lead $LEAD_FIRSTNAME $LEAD_LASTNAME"
  salesforce_sfdx_with_retry --stdin "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF
Database.delete([SELECT Id FROM Lead WHERE FirstName = '$LEAD_FIRSTNAME' AND LastName = '$LEAD_LASTNAME'], false);
EOF
  [ $? -ne 0 ] && cleanup_failed=1
  if [ $cleanup_failed -ne 0 ]
  then
    logwarn "⚠️ cleanup did not complete - test records may be left behind in the org"
  fi
  set -e
}
trap cleanup_salesforce_test_data EXIT

DOMAIN=$(echo $SALESFORCE_INSTANCE | cut -d "/" -f 3)
IP=$(nslookup $DOMAIN | grep Address | grep -v "#" | cut -d " " -f 2 | tail -1)
log "Blocking $DOMAIN IP $IP to make sure proxy is used"
playground debug block-traffic --container connect --destination $IP --action start

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
     "http.proxy": "nginx-proxy:8888",
     "connection.max.message.size": "10048576",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF



sleep 10

log "Verify we have received the data in sfdc-bulkapi-leads topic"
playground topic consume --topic sfdc-bulkapi-leads --min-expected-messages 1 --timeout 60