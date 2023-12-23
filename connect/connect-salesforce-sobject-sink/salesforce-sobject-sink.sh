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

# second account (for SObject sink)
SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
SALESFORCE_SECURITY_TOKEN_ACCOUNT2=${SALESFORCE_SECURITY_TOKEN_ACCOUNT2:-$8}
SALESFORCE_CONSUMER_KEY_ACCOUNT2=${SALESFORCE_CONSUMER_KEY_ACCOUNT2:-$9}
SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2=${SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2:-$10}
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

if [ -z "$SALESFORCE_CONSUMER_KEY_ACCOUNT2" ]
then
     logerror "SALESFORCE_CONSUMER_KEY_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2" ]
then
     logerror "SALESFORCE_CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PUSH_TOPICS_NAME=MyLeadPushTopics${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ../../connect/connect-salesforce-sobject-sink/MyLeadPushTopics-template.apex > ../../connect/connect-salesforce-sobject-sink/MyLeadPushTopics.apex

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# the Salesforce PushTopic source connector is used to get data into Kafka and the Salesforce SObject sink connector is used to export data from Kafka to Salesforce

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

log "Creating Salesforce PushTopics Source connector"
playground connector create-or-update --connector salesforce-pushtopic-source << EOF
{
     "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
     "kafka.topic": "sfdc-pushtopic-leads",
     "tasks.max": "1",
     "curl.logging": "true",
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
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

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
playground connector create-or-update --connector salesforce-sobject-sink << EOF
{
     "connector.class": "io.confluent.salesforce.SalesforceSObjectSinkConnector",
     "topics": "sfdc-pushtopic-leads",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.object" : "Lead",
     "salesforce.instance" : "$SALESFORCE_INSTANCE_ACCOUNT2",
     "salesforce.username" : "$SALESFORCE_USERNAME_ACCOUNT2",
     "salesforce.password" : "$SALESFORCE_PASSWORD_ACCOUNT2",
     "salesforce.password.token" : "$SALESFORCE_SECURITY_TOKEN_ACCOUNT2",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY_ACCOUNT2",
     "salesforce.consumer.secret" : "$SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2",
     "salesforce.use.custom.id.field" : "true",
     "salesforce.custom.id.field.name" : "CustomId__c",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "salesforce.ignore.fields" : "CleanStatus",
     "salesforce.ignore.reference.fields" : "true",
     "override.event.type": "true",
     "salesforce.sink.object.operation": "upsert",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF



sleep 10

log "Verify topic success-responses"
playground topic consume --topic success-responses --min-expected-messages 1 --timeout 60

# log "Verify topic error-responses"
playground topic consume --topic error-responses --min-expected-messages 0 --timeout 60

log "Login with sfdx CLI on the account #2"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\""

log "Get the Lead created on account #2"
docker exec sfdx-cli sh -c "sfdx force:data:record:get  -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -w \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\"" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "$LEAD_FIRSTNAME" /tmp/result.log
