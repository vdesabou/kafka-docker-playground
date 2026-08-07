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


# second account (for SObject sink)
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

if [ -z "$SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2" ]
then
     logerror "SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2 is not set. Export it as environment variable or pass it as argument. Check README !"
     exit 1
fi



# Unique per test - see the comment in salesforce-pushtopic-source.sh. Sharing
# one PushTopic name across tests breaks concurrent runs against the same org.
PUSH_TOPICS_NAME=sobjLead${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}
if [ ${#PUSH_TOPICS_NAME} -gt 25 ]; then
  PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME:0:25}
fi

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ../../connect/connect-salesforce-sobject-sink/MyLeadPushTopics-template.apex > ../../connect/connect-salesforce-sobject-sink/MyLeadPushTopics.apex

salesforce_ensure_jwt_keystore "$PWD" > /dev/null

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# the Salesforce PushTopic source connector is used to get data into Kafka and the Salesforce SObject sink connector is used to export data from Kafka to Salesforce

log "Login with sfdx CLI"
salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

log "Delete $PUSH_TOPICS_NAME, if required"
set +e
# Expected to fail when the PushTopic does not exist yet, so deliberately NOT routed
# through salesforce_sfdx_with_retry: retrying a step whose failure is normal would
# spend this test's shared retry budget, and trigger a pointless re-authentication.
playground container exec --container sfdx-cli --command "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF --shell sh
List<PushTopic> pts = [SELECT Id FROM PushTopic WHERE Name = '$PUSH_TOPICS_NAME'];
Database.delete(pts);
EOF
set -e
log "Create $PUSH_TOPICS_NAME"
salesforce_sfdx_with_retry "sfdx apex run --target-org \"$SALESFORCE_USERNAME\" -f \"/tmp/MyLeadPushTopics.apex\""

log "Creating Salesforce PushTopics Source connector"
salesforce_create_connector_with_retry salesforce-pushtopic-source << EOF
{
     "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
     "kafka.topic": "sfdc-pushtopic-leads",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.object" : "Lead",
     "salesforce.push.topic.name" : "$PUSH_TOPICS_NAME",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.username" : "$SALESFORCE_USERNAME",
     "salesforce.grant.type" : "JWT_BEARER",
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

sleep 30

log "Verify we have received the data in sfdc-pushtopic-leads topic"
playground topic consume --topic sfdc-pushtopic-leads --min-expected-messages 1 --timeout 60

# {
#   "schema": {
#     "type": "struct",
#     "fields": [
#       {
#         "type": "string",
#         "optional": false,
#         "doc": "Unique identifier for the object.",
#         "field": "Id"
#       }
#     ],
#     "optional": false,
#     "name": "io.confluent.salesforce.LeadKey"
#   },
#   "payload": {
#     "Id": "00Q7R00001lsWLiUAM"
#   }
# }

# {
#   "schema": {
#     "type": "struct",
#     "fields": [
#       {
#         "type": "string",
#         "optional": false,
#         "doc": "Unique identifier for the object.",
#         "field": "Id"
#       },
#       {
#         "type": "boolean",
#         "optional": true,
#         "field": "IsDeleted"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "MasterRecordId"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "LastName"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "FirstName"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Salutation"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Name"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Title"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Company"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Street"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "City"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "State"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "PostalCode"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Country"
#       },
#       {
#         "type": "double",
#         "optional": true,
#         "field": "Latitude"
#       },
#       {
#         "type": "double",
#         "optional": true,
#         "field": "Longitude"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "GeocodeAccuracy"
#       },
#       {
#         "type": "struct",
#         "fields": [
#           {
#             "type": "string",
#             "optional": true,
#             "field": "GeocodeAccuracy"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "doc": "",
#             "field": "State"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "field": "Street"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "field": "PostalCode"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "field": "Country"
#           },
#           {
#             "type": "double",
#             "optional": true,
#             "field": "Latitude"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "field": "City"
#           },
#           {
#             "type": "double",
#             "optional": true,
#             "field": "Longitude"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "field": "CountryCode"
#           },
#           {
#             "type": "string",
#             "optional": true,
#             "field": "StateCode"
#           }
#         ],
#         "optional": true,
#         "name": "io.confluent.salesforce.Address",
#         "field": "Address"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Phone"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "MobilePhone"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Fax"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Email"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Website"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "PhotoUrl"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Description"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "LeadSource"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Status"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Industry"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Rating"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "AnnualRevenue"
#       },
#       {
#         "type": "int32",
#         "optional": true,
#         "field": "NumberOfEmployees"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "OwnerId"
#       },
#       {
#         "type": "boolean",
#         "optional": true,
#         "field": "IsConverted"
#       },
#       {
#         "type": "int32",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Date",
#         "version": 1,
#         "field": "ConvertedDate"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "ConvertedAccountId"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "ConvertedContactId"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "ConvertedOpportunityId"
#       },
#       {
#         "type": "boolean",
#         "optional": true,
#         "field": "IsUnreadByOwner"
#       },
#       {
#         "type": "int64",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Timestamp",
#         "version": 1,
#         "field": "CreatedDate"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "CreatedById"
#       },
#       {
#         "type": "int64",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Timestamp",
#         "version": 1,
#         "field": "LastModifiedDate"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "LastModifiedById"
#       },
#       {
#         "type": "int64",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Timestamp",
#         "version": 1,
#         "field": "SystemModstamp"
#       },
#       {
#         "type": "int32",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Date",
#         "version": 1,
#         "field": "LastActivityDate"
#       },
#       {
#         "type": "int64",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Timestamp",
#         "version": 1,
#         "field": "LastViewedDate"
#       },
#       {
#         "type": "int64",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Timestamp",
#         "version": 1,
#         "field": "LastReferencedDate"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Jigsaw"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "JigsawContactId"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "CleanStatus"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "CompanyDunsNumber"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "DandbCompanyId"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "EmailBouncedReason"
#       },
#       {
#         "type": "int64",
#         "optional": true,
#         "name": "org.apache.kafka.connect.data.Timestamp",
#         "version": 1,
#         "field": "EmailBouncedDate"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "IndividualId"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "SICCode__c"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "ProductInterest__c"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "Primary__c"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "CurrentGenerators__c"
#       },
#       {
#         "type": "double",
#         "optional": true,
#         "field": "NumberofLocations__c"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "CustomId__c"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "_ObjectType"
#       },
#       {
#         "type": "string",
#         "optional": true,
#         "field": "_EventType"
#       }
#     ],
#     "optional": false,
#     "name": "io.confluent.salesforce.Lead"
#   },
#   "payload": {
#     "Id": "00Q7R00001lsWLiUAM",
#     "IsDeleted": false,
#     "MasterRecordId": null,
#     "LastName": "Doe_28736",
#     "FirstName": "John_5872",
#     "Salutation": null,
#     "Name": "John_5872 Doe_28736",
#     "Title": null,
#     "Company": "Confluent",
#     "Street": null,
#     "City": null,
#     "State": null,
#     "PostalCode": null,
#     "Country": null,
#     "Latitude": null,
#     "Longitude": null,
#     "GeocodeAccuracy": null,
#     "Address": {
#       "GeocodeAccuracy": null,
#       "State": null,
#       "Street": null,
#       "PostalCode": null,
#       "Country": null,
#       "Latitude": null,
#       "City": null,
#       "Longitude": null,
#       "CountryCode": null,
#       "StateCode": null
#     },
#     "Phone": null,
#     "MobilePhone": null,
#     "Fax": null,
#     "Email": null,
#     "Website": null,
#     "PhotoUrl": null,
#     "Description": null,
#     "LeadSource": null,
#     "Status": "Open - Not Contacted",
#     "Industry": null,
#     "Rating": null,
#     "AnnualRevenue": null,
#     "NumberOfEmployees": null,
#     "OwnerId": "0052X00000AJGNCQA5",
#     "IsConverted": false,
#     "ConvertedDate": null,
#     "ConvertedAccountId": null,
#     "ConvertedContactId": null,
#     "ConvertedOpportunityId": null,
#     "IsUnreadByOwner": true,
#     "CreatedDate": 1670582776000,
#     "CreatedById": "0052X00000AJGNCQA5",
#     "LastModifiedDate": 1670582776000,
#     "LastModifiedById": "0052X00000AJGNCQA5",
#     "SystemModstamp": 1670582776000,
#     "LastActivityDate": null,
#     "LastViewedDate": null,
#     "LastReferencedDate": null,
#     "Jigsaw": null,
#     "JigsawContactId": null,
#     "CleanStatus": "5",
#     "CompanyDunsNumber": null,
#     "DandbCompanyId": null,
#     "EmailBouncedReason": null,
#     "EmailBouncedDate": null,
#     "IndividualId": null,
#     "SICCode__c": null,
#     "ProductInterest__c": null,
#     "Primary__c": null,
#     "CurrentGenerators__c": null,
#     "NumberofLocations__c": null,
#     "CustomId__c": null,
#     "_ObjectType": "Lead",
#     "_EventType": "created"
#   }
# }

log "Creating Salesforce SObject Sink connector"
salesforce_create_connector_with_retry salesforce-sobject-sink << EOF
{
    "connector.class": "io.confluent.salesforce.SalesforceSObjectSinkConnector",
    "topics": "sfdc-pushtopic-leads",
    "tasks.max": "1",
    "curl.logging": "true",
    "salesforce.object" : "Lead",
    "salesforce.instance" : "$SALESFORCE_INSTANCE_ACCOUNT2",
    "salesforce.username" : "$SALESFORCE_USERNAME_ACCOUNT2",
     "salesforce.grant.type" : "JWT_BEARER",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2",
     "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
     "salesforce.jwt.keystore.password": "confluent",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "salesforce.ignore.fields" : "CleanStatus",
    "salesforce.ignore.reference.fields" : "true",
    "override.event.type": "true",
    "salesforce.sink.object.operation": "insert",
    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "request.max.retries.time.ms": "10000"
}
EOF



sleep 10

# 180s, not 60s: the sink reports to success-responses only after its writes to
# Salesforce complete, which was observed exceeding 60s.
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
