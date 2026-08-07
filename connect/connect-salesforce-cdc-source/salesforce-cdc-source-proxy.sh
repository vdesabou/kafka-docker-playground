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
SALESFORCE_CONSUMER_KEY_WITH_JWT=${SALESFORCE_CONSUMER_KEY_WITH_JWT:-$3}
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


if [ -z "$SALESFORCE_CONSUMER_KEY_WITH_JWT" ]
then
     logerror "SALESFORCE_CONSUMER_KEY_WITH_JWT is not set. Export it as environment variable or pass it as argument. Check README !"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

salesforce_ensure_jwt_keystore "$PWD" > /dev/null

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

DOMAIN=$(echo $SALESFORCE_INSTANCE | cut -d "/" -f 3)
IP=$(nslookup $DOMAIN | grep Address | grep -v "#" | cut -d " " -f 2 | tail -1)
log "Blocking $DOMAIN IP $IP to make sure proxy is used"
playground debug block-traffic --container connect --destination $IP --action start

log "Creating Salesforce CDC Source connector"
salesforce_create_connector_with_retry salesforce-cdc-source << EOF
{
     "connector.class": "io.confluent.salesforce.SalesforceCdcSourceConnector",
     "kafka.topic": "sfdc-cdc-contacts",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.cdc.name" : "ContactChangeEvent",
     "__comment" : "from 2.0.0 salesforce.cdc.name is renamed salesforce.cdc.channel",
     "salesforce.cdc.channel" : "ContactChangeEvent",
     "salesforce.grant.type" : "JWT_BEARER",
     "salesforce.username" : "$SALESFORCE_USERNAME",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY_WITH_JWT",
     "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
     "salesforce.jwt.keystore.password": "confluent",
     "http.proxy": "nginx-proxy:8888",
     "salesforce.initial.start" : "latest",
     "connection.max.message.size": "10048576",
     "_comment:": "fixing com.sforce.ws.ConnectionException: RESOURCE_NOT_FOUNDNot a valid enumeration", 
     "salesforce.version": "64.0",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Login with sfdx CLI"
salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

CONTACT_FIRSTNAME=John_$RANDOM
CONTACT_LASTNAME=Doe_$RANDOM
log "Add a Contact to Salesforce: $CONTACT_FIRSTNAME $CONTACT_LASTNAME"
salesforce_sfdx_with_retry "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Contact -v \"FirstName='$CONTACT_FIRSTNAME' LastName='$CONTACT_LASTNAME'\""

# Remove the records this test created, so repeated runs do not accumulate data in a
# shared Salesforce org. Only the exact records created above are matched. An EXIT trap,
# so cleanup also happens when an assertion fails.
cleanup_salesforce_test_data() {
  set +e
  salesforce_cleanup_records "$SALESFORCE_USERNAME" "$SALESFORCE_PASSWORD" "$SALESFORCE_SECURITY_TOKEN" "$SALESFORCE_INSTANCE" \
    "Contact:FirstName = '$CONTACT_FIRSTNAME' AND LastName = '$CONTACT_LASTNAME'"
  set -e
}
trap cleanup_salesforce_test_data EXIT

sleep 10

log "Verify we have received the data in sfdc-cdc-contacts topic"
playground topic consume --topic sfdc-cdc-contacts --min-expected-messages 1 --timeout 180