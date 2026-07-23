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
SALESFORCE_CONSUMER_KEY=${SALESFORCE_CONSUMER_KEY:-$3}
SALESFORCE_CONSUMER_PASSWORD=${SALESFORCE_CONSUMER_PASSWORD:-$4}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$5}
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

salesforce_ensure_jwt_keystore "$PWD" > /dev/null

PUSH_TOPICS_NAME=MyLeadPushTopics${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}
if [ ${#PUSH_TOPICS_NAME} -gt 25 ]; then
  PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME:0:25}
fi

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ../../connect/connect-salesforce-pushtopics-source/MyLeadPushTopics-template.apex > ../../connect/connect-salesforce-pushtopics-source/MyLeadPushTopics.apex

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Login with sfdx CLI"
playground container exec --container sfdx-cli --command "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\"" --shell sh

log "Delete $PUSH_TOPICS_NAME, if required"
set +e
playground container exec --container sfdx-cli --command "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" --shell sh << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic WHERE Name = '$PUSH_TOPICS_NAME'];
Database.delete(pts);
EOF
set -e
log "Create $PUSH_TOPICS_NAME"
playground container exec --container sfdx-cli --command "sfdx apex run --target-org \"$SALESFORCE_USERNAME\" -f \"/tmp/MyLeadPushTopics.apex\"" --shell sh

log "Creating Salesforce PushTopics Source connector"
playground connector create-or-update --connector salesforce-pushtopic-source  << EOF
{
     "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
     "kafka.topic": "sfdc-pushtopic-leads",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.object" : "Lead",
     "salesforce.push.topic.name" : "$PUSH_TOPICS_NAME",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.grant.type" : "JWT_BEARER",
     "salesforce.username" : "$SALESFORCE_USERNAME",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY_WITH_JWT",
     "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
     "salesforce.jwt.keystore.password": "confluent",
     "salesforce.initial.start" : "latest",
     "connection.max.message.size": "10048576",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
playground container exec --container sfdx-cli --command "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\"" --shell sh

sleep 30

log "Verify we have received the data in sfdc-pushtopic-leads topic"
playground topic consume --topic sfdc-pushtopic-leads --min-expected-messages 1 --timeout 60