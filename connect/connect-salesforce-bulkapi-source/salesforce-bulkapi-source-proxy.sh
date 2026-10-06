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

if [ -z "$SALESFORCE_CONSUMER_KEY_WITH_JWT" ]
then
     logerror "SALESFORCE_CONSUMER_KEY_WITH_JWT is not set. Export it as environment variable or pass it as argument. Check README !"
     exit 1
fi

# JWT_BEARER for the Bulk API connector arrived on 3.0.x and 3.1.x independently, so the grant
# is picked from the version actually under test - see salesforce_bulkapi_supports_jwt in
# utils.sh. JWT is preferred: with the password grant Salesforce shares one session across
# identical logins by the same user, so the logout() done by any connector validation (Connect's
# own, or the CLI's show-config-parameters right after creation) kills the session the task is
# using and it fails with INVALID_SESSION_ID. The password grant is kept for older versions.
SALESFORCE_CONNECTOR_VERSION="$(salesforce_connector_version)"
if salesforce_bulkapi_supports_jwt "$SALESFORCE_CONNECTOR_VERSION"
then
  SALESFORCE_GRANT=JWT_BEARER
else
  SALESFORCE_GRANT=PASSWORD
fi
log "🔐 connector ${SALESFORCE_CONNECTOR_VERSION:-unknown} -> authenticating with $SALESFORCE_GRANT"

if [ "$SALESFORCE_GRANT" = "JWT_BEARER" ]
then
  # docker-compose.plaintext.proxy.yml already mounts the keystore into connect at /tmp.
  salesforce_ensure_jwt_keystore "$PWD" > /dev/null
  SALESFORCE_SOURCE_AUTH="\"salesforce.grant.type\" : \"JWT_BEARER\",
     \"salesforce.username\" : \"$SALESFORCE_USERNAME\",
     \"salesforce.consumer.key\" : \"$SALESFORCE_CONSUMER_KEY_WITH_JWT\",
     \"salesforce.jwt.keystore.path\" : \"/tmp/salesforce-confluent.keystore.jks\",
     \"salesforce.jwt.keystore.password\" : \"confluent\","
else
  SALESFORCE_SOURCE_AUTH="\"salesforce.username\" : \"$SALESFORCE_USERNAME\",
     \"salesforce.password\" : \"$SALESFORCE_PASSWORD\",
     \"salesforce.password.token\" : \"$SALESFORCE_SECURITY_TOKEN\","
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

log "Login with sfdx CLI"
salesforce_sfdx_login "$SALESFORCE_USERNAME" "$SALESFORCE_CONSUMER_KEY_WITH_JWT" "$SALESFORCE_INSTANCE"

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
salesforce_sfdx_with_retry "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

# Remove the records this test created, so repeated runs do not accumulate data in a
# shared Salesforce org. Only the exact records created above are matched. An EXIT trap,
# so cleanup also happens when an assertion fails.
cleanup_salesforce_test_data() {
  set +e
  salesforce_cleanup_records "$SALESFORCE_USERNAME" "$SALESFORCE_CONSUMER_KEY_WITH_JWT" "$SALESFORCE_INSTANCE" \
    "Lead:FirstName = '$LEAD_FIRSTNAME' AND LastName = '$LEAD_LASTNAME'"
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
     $SALESFORCE_SOURCE_AUTH
     "http.proxy": "nginx-proxy:8888",
     "connection.max.message.size": "10048576",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

# Fails with the task's trace on any FAILED state other than INVALID_SESSION_ID, which only
# the password grant can hit and which a task restart recovers from.
restart_task_on_invalid_session salesforce-bulkapi-source



sleep 10

log "Verify we have received the data in sfdc-bulkapi-leads topic"
playground topic consume --topic sfdc-bulkapi-leads --min-expected-messages 1 --timeout 60