#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
SALESFORCE_CONSUMER_KEY=${SALESFORCE_CONSUMER_KEY:-$3}
SALESFORCE_CONSUMER_PASSWORD=${SALESFORCE_CONSUMER_PASSWORD:-$4}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$5}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

# second account (for Bulk API sink)
SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
SALESFORCE_SECURITY_TOKEN_ACCOUNT2=${SALESFORCE_SECURITY_TOKEN_ACCOUNT2:-$8}
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


if [ -z "$SALESFORCE_CONSUMER_KEY" ]
then
     logerror "SALESFORCE_CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_CONSUMER_PASSWORD" ]
then
     logerror "SALESFORCE_CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
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

PUSH_TOPICS_NAME=MyLeadPushTopicsV2${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ../../ccloud/fm-salesforce-pushtopics-source/MyLeadPushTopics-template.apex > ../../ccloud/fm-salesforce-pushtopics-source/MyLeadPushTopics.apex

bootstrap_ccloud_environment



set +e
playground topic delete --topic sfdc-pushtopic-leads
sleep 3
playground topic create --topic sfdc-pushtopic-leads
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

log "Delete $PUSH_TOPICS_NAME, if required"
set +e
docker exec -i sfdx-cli sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic WHERE Name = '$PUSH_TOPICS_NAME'];
Database.delete(pts);
EOF
set -e
log "Create $PUSH_TOPICS_NAME"
docker exec sfdx-cli sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\" -f \"/tmp/MyLeadPushTopics.apex\""



connector_name="SFDCPushTopicSourceBulkAPI2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "SalesforcePushTopicSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "kafka.topic": "sfdc-pushtopic-leads",
     "salesforce.object" : "Lead",
     "salesforce.push.topic.name" : "$PUSH_TOPICS_NAME",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.username" : "$SALESFORCE_USERNAME",
     "salesforce.password" : "$SALESFORCE_PASSWORD",
     "salesforce.password.token" : "$SALESFORCE_SECURITY_TOKEN",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY",
     "salesforce.consumer.secret" : "$SALESFORCE_CONSUMER_PASSWORD",
     "salesforce.initial.start" : "latest",
     "connection.max.message.size": "10048576",
     "output.data.format": "AVRO",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

sleep 30

log "Verify we have received the data in sfdc-pushtopic-leads topic"
playground topic consume --topic sfdc-pushtopic-leads --min-expected-messages 1 --timeout 60


connector_name2="SalesforceBulkApiV2Sink_$USER"
set +e
playground connector delete --connector $connector_name2 > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name2 << EOF
{
     "connector.class": "SalesforceBulkApiV2Sink",
     "name": "$connector_name2",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topics": "sfdc-pushtopic-leads",
     "salesforce.object" : "Lead",
     "salesforce.instance" : "$SALESFORCE_INSTANCE_ACCOUNT2",
     "salesforce.username" : "$SALESFORCE_USERNAME_ACCOUNT2",
     "salesforce.password" : "$SALESFORCE_PASSWORD_ACCOUNT2",
     "salesforce.password.token" : "$SALESFORCE_SECURITY_TOKEN_ACCOUNT2",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY_ACCOUNT2",
     "salesforce.consumer.secret" : "$SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2",
     "salesforce.ignore.fields" : "CleanStatus",
     "salesforce.ignore.reference.fields" : "true",
     "input.data.format": "AVRO",
     "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name2 600


sleep 10

connectorId2=$(get_ccloud_connector_lcc $connector_name2)

log "Verifying topic success-$connectorId2"
playground topic consume --topic success-$connectorId2 --min-expected-messages 1 --timeout 60

# log "Verify topic error-responses"
playground topic consume --topic error-$connectorId2 --min-expected-messages 0 --timeout 60

log "Login with sfdx CLI on the account #2"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\""

log "Get the Lead created on account #2"
docker exec sfdx-cli sh -c "sfdx data:record:get --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -w \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\"" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "$LEAD_FIRSTNAME" /tmp/result.log


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

log "Do you want to delete the fully managed connector $connector_name2 ?"
check_if_continue

playground connector delete --connector $connector_name2