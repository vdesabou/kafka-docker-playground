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

SALESFORCE_CONSUMER_KEY_WITH_JWT=${SALESFORCE_CONSUMER_KEY_WITH_JWT:-$3}
SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$4}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}


# second account (for Bulk API sink)
SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$5}
SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$6}
SALESFORCE_SECURITY_TOKEN_ACCOUNT2=${SALESFORCE_SECURITY_TOKEN_ACCOUNT2:-$7}
SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2=${SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2:-$8}
SALESFORCE_INSTANCE_ACCOUNT2=${SALESFORCE_INSTANCE_ACCOUNT2:-"https://login.salesforce.com"}

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

if [ -z "$SALESFORCE_USERNAME_ACCOUNT2" ]
then
     logerror "SALESFORCE_USERNAME_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD_ACCOUNT2" ]
then
     logerror "SALESFORCE_PASSWORD_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN_ACCOUNT2" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# Unique per test - see the comment in salesforce-pushtopic-source.sh. Sharing
# one PushTopic name across tests breaks concurrent runs against the same org.
PUSH_TOPICS_NAME=bulksinkLead${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}
if [ ${#PUSH_TOPICS_NAME} -gt 25 ]; then
  PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME:0:25}
fi

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
     ../../connect/connect-salesforce-bulkapi-sink/MyLeadPushTopics-template.apex > ../../connect/connect-salesforce-bulkapi-sink/MyLeadPushTopics.apex


# JWT_BEARER for the Bulk API connector arrived in 3.1.9; older artifacts only support the
# username-password SOAP grant. Rather than duplicating this test per grant, or skipping it
# on older artifacts, pick the grant from the version actually under test. An undeterminable
# version falls back to username-password, which every version supports.
SALESFORCE_CONNECTOR_VERSION="$(salesforce_connector_version)"
if [ -n "$SALESFORCE_CONNECTOR_VERSION" ] && ! version_gt "3.1.9" "$SALESFORCE_CONNECTOR_VERSION"
then
  SALESFORCE_GRANT=JWT_BEARER
else
  SALESFORCE_GRANT=PASSWORD
fi
log "🔐 connector ${SALESFORCE_CONNECTOR_VERSION:-unknown} -> authenticating with $SALESFORCE_GRANT"

if [ "$SALESFORCE_GRANT" = "JWT_BEARER" ]
then
  for v in SALESFORCE_CONSUMER_KEY_WITH_JWT SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2
  do
    if [ -z "${!v}" ]
    then
         logerror "$v is not set. Export it as environment variable or pass it as argument. Check README !"
         exit 1
    fi
  done
  # Both orgs' connected apps trust the same certificate, so one keystore covers source and
  # sink. docker-compose.plaintext.yml already mounts it into connect at /tmp.
  salesforce_ensure_jwt_keystore "$PWD" > /dev/null

  SALESFORCE_SOURCE_AUTH="\"salesforce.grant.type\" : \"JWT_BEARER\",
     \"salesforce.username\" : \"$SALESFORCE_USERNAME\",
     \"salesforce.consumer.key\" : \"$SALESFORCE_CONSUMER_KEY_WITH_JWT\",
     \"salesforce.jwt.keystore.path\" : \"/tmp/salesforce-confluent.keystore.jks\",
     \"salesforce.jwt.keystore.password\" : \"confluent\","
  SALESFORCE_SINK_AUTH="\"salesforce.grant.type\" : \"JWT_BEARER\",
     \"salesforce.username\" : \"$SALESFORCE_USERNAME_ACCOUNT2\",
     \"salesforce.consumer.key\" : \"$SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2\",
     \"salesforce.jwt.keystore.path\" : \"/tmp/salesforce-confluent.keystore.jks\",
     \"salesforce.jwt.keystore.password\" : \"confluent\","
else
  SALESFORCE_SOURCE_AUTH="\"salesforce.username\" : \"$SALESFORCE_USERNAME\",
     \"salesforce.password\" : \"$SALESFORCE_PASSWORD\",
     \"salesforce.password.token\" : \"$SALESFORCE_SECURITY_TOKEN\","
  SALESFORCE_SINK_AUTH="\"salesforce.username\" : \"$SALESFORCE_USERNAME_ACCOUNT2\",
     \"salesforce.password\" : \"$SALESFORCE_PASSWORD_ACCOUNT2\",
     \"salesforce.password.token\" : \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\","
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Login with sfdx CLI"
salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
salesforce_sfdx_with_retry "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

# Remove the records this test created, so repeated runs do not accumulate data in a
# shared Salesforce org. Only the exact records created above are matched. An EXIT trap,
# so cleanup also happens when an assertion fails.
cleanup_salesforce_test_data() {
  set +e
  salesforce_cleanup_records "$SALESFORCE_USERNAME" "$SALESFORCE_PASSWORD" "$SALESFORCE_SECURITY_TOKEN" "$SALESFORCE_INSTANCE" \
    "Lead:FirstName = '$LEAD_FIRSTNAME' AND LastName = '$LEAD_LASTNAME'" \
    "PushTopic:Name = '$PUSH_TOPICS_NAME'"
  salesforce_cleanup_records "$SALESFORCE_USERNAME_ACCOUNT2" "$SALESFORCE_PASSWORD_ACCOUNT2" "$SALESFORCE_SECURITY_TOKEN_ACCOUNT2" "$SALESFORCE_INSTANCE_ACCOUNT2" \
    "Lead:FirstName = '$LEAD_FIRSTNAME' AND LastName = '$LEAD_LASTNAME'"
  set -e
}
trap cleanup_salesforce_test_data EXIT


log "Creating Salesforce Bulk API Source connector"
salesforce_create_connector_with_retry salesforce-bulkapi-source << EOF
{
     "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSourceConnector",
     "kafka.topic": "sfdc-bulkapi-leads",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.object" : "Lead",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     $SALESFORCE_SOURCE_AUTH
     "connection.max.message.size": "10048576",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

# Called for both grants. Despite its name this is also the only place this test asserts
# the task reached RUNNING: it fails with the task's stack trace on any other FAILED
# state, and fails if the task never comes up within 120s. Gating it on the password
# grant removed that assertion from the JWT path - the path CI takes - leaving a genuine
# task failure to surface only as "topic contains 0 messages" with no trace. Its
# INVALID_SESSION_ID branch simply never fires under JWT.
restart_task_on_invalid_session salesforce-bulkapi-source

# 180s, not 60s: the Bulk API query job runs asynchronously on a Salesforce-side
# queue, so its completion time is not under this test's control.
log "Verify we have received the data in sfdc-bulkapi-leads topic"
playground topic consume --topic sfdc-bulkapi-leads --min-expected-messages 1 --timeout 180

log "Creating Salesforce Bulk API Sink connector"
salesforce_create_connector_with_retry salesforce-bulkapi-sink << EOF
{
    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSinkConnector",
    "topics": "sfdc-bulkapi-leads",
    "tasks.max": "1",
    "curl.logging": "true",
    "salesforce.object" : "Lead",
    "salesforce.instance" : "$SALESFORCE_INSTANCE_ACCOUNT2",
    $SALESFORCE_SINK_AUTH
    "salesforce.ignore.fields" : "CleanStatus",
    "salesforce.ignore.reference.fields" : "true",
    "connection.max.message.size": "10048576",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "transforms" : "InsertField",
    "transforms.InsertField.type" : "org.apache.kafka.connect.transforms.InsertField\$Value",
    "transforms.InsertField.static.field" : "_EventType",
    "transforms.InsertField.static.value" : "created",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

# Called for both grants. Despite its name this is also the only place this test asserts
# the task reached RUNNING: it fails with the task's stack trace on any other FAILED
# state, and fails if the task never comes up within 120s. Gating it on the password
# grant removed that assertion from the JWT path - the path CI takes - leaving a genuine
# task failure to surface only as "topic contains 0 messages" with no trace. Its
# INVALID_SESSION_ID branch simply never fires under JWT.
restart_task_on_invalid_session salesforce-bulkapi-sink

sleep 30

# 180s, not 60s: the sink reports to success-responses only once the Bulk API v2
# ingest job reaches JobComplete, and that job is processed asynchronously on a
# Salesforce-side queue. With an unchanged test and identical input this was
# observed both completing well inside 60s and exceeding it, so 60s made this
# assertion flaky rather than meaningful.
log "Verify topic success-responses"
playground topic consume --topic success-responses --min-expected-messages 1 --timeout 180

log "Verify the connector reported no errors"
salesforce_assert_topic_empty error-responses

log "Login with sfdx CLI on the account #2"
salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\""

log "Get the Lead created on account #2"
# data:query, not data:record:get: the sink inserts (it never upserts), so a shared org
# accumulates Leads and an aborted run can leave one behind. data:record:get then fails
# with "is not a unique qualifier for Lead; N records were retrieved" even though the
# record the test just wrote is present. data:query returns every match, and the grep
# below still fails if the record is genuinely missing.
# || true so cat always runs - without it set -e aborts here and the error is never shown.
playground container exec --container sfdx-cli --command "sfdx data:query --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\" -q \"SELECT Id, FirstName, LastName FROM Lead WHERE FirstName='$LEAD_FIRSTNAME' AND LastName='$LEAD_LASTNAME' AND Company='Confluent'\"" --shell sh > /tmp/result.log 2>&1 || true
cat /tmp/result.log
grep "$LEAD_FIRSTNAME" /tmp/result.log
