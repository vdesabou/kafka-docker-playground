#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

bootstrap_ccloud_environment



set +e
playground topic delete --topic sfdc-cdc-contacts
sleep 3
playground topic create --topic sfdc-cdc-contacts
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

base64_truststore=$(salesforce_get_jwt_keystore_base64 "$PWD")

connector_name="SalesforceCdcSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "SalesforceCdcSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "kafka.topic": "sfdc-cdc-contacts",
     "salesforce.grant.type" : "JWT_BEARER",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.username": "$SALESFORCE_USERNAME",

     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY_WITH_JWT",
     "salesforce.jwt.keystore.file": "data:text/plain;base64,$base64_truststore",
     "salesforce.jwt.keystore.password": "confluent",

     "salesforce.cdc.name": "ContactChangeEvent",
     "output.data.format": "JSON",
     "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Login with sfdx CLI"
salesforce_sfdx_login "$SALESFORCE_USERNAME" "$SALESFORCE_CONSUMER_KEY_WITH_JWT" "$SALESFORCE_INSTANCE"

CONTACT_FIRSTNAME=John_$RANDOM
CONTACT_LASTNAME=Doe_$RANDOM
log "Add a Contact to Salesforce: $CONTACT_FIRSTNAME $CONTACT_LASTNAME"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Contact -v \"FirstName='$CONTACT_FIRSTNAME' LastName='$CONTACT_LASTNAME'\""

# Remove the records this test created, so repeated runs do not accumulate data in a
# shared Salesforce org. Only the exact records created above are matched. An EXIT trap,
# so cleanup also happens when an assertion fails.
cleanup_salesforce_test_data() {
  set +e
  salesforce_cleanup_records "$SALESFORCE_USERNAME" "$SALESFORCE_CONSUMER_KEY_WITH_JWT" "$SALESFORCE_INSTANCE" \
    "Contact:FirstName = '$CONTACT_FIRSTNAME' AND LastName = '$CONTACT_LASTNAME'"
  set -e
}
trap cleanup_salesforce_test_data EXIT

sleep 10

log "Verify we have received the data in sfdc-cdc-contacts topic"
playground topic consume --topic sfdc-cdc-contacts --min-expected-messages 1 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name