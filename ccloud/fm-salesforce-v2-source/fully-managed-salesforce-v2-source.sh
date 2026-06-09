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

bootstrap_ccloud_environment



set +e
playground topic delete --topic salesforce.Lead
sleep 3
playground topic create --topic salesforce.Lead
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

connector_name="SalesforceSourceV2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

TODAY=$(date -u '+%Y-%m-%d')
log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "SalesforceSourceV2",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "salesforce.grant.type": "PASSWORD",
    "salesforce.instance" : "$SALESFORCE_INSTANCE",
    "salesforce.username": "$SALESFORCE_USERNAME",
    "salesforce.password": "$SALESFORCE_PASSWORD",
    "salesforce.password.token": "$SALESFORCE_SECURITY_TOKEN",
    "salesforce.consumer.key": "$SALESFORCE_CONSUMER_KEY",
    "salesforce.consumer.secret": "$SALESFORCE_CONSUMER_PASSWORD",
    "sobject.names" : "Lead",
    "topic.prefix": "salesforce",
    "since": "$TODAY",
    "output.data.format": "AVRO",
    "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

sleep 10

log "Verify we have received the data in salesforce.Lead topic"
playground topic consume --topic salesforce.Lead --min-expected-messages 1 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name


# 11:10:01 ℹ️ ✨ Display content of topic salesforce.Lead, it contains 1 messages
# 11:10:01 ℹ️ 🔮🙅 topic is not using any schema for key
# 11:10:01 ℹ️ 🔮🔰 topic is using avro for value
# 11:10:03 ℹ️ 🔰 subject salesforce.Lead-value 💯 version 1 (id 100106)
# {
#   "type": "record",
#   "name": "Lead",
#   "namespace": "io.confluent.salesforce",
#   "fields": [
#     {
#       "name": "Id",
#       "type": "string"
#     },
#     {
#       "name": "IsDeleted",
#       "type": [
#         "null",
#         "boolean"
#       ],
#       "default": null
#     },
#     {
#       "name": "MasterRecordId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "LastName",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "FirstName",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Salutation",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Name",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Title",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Company",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Street",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "City",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "State",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "PostalCode",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Country",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Latitude",
#       "type": [
#         "null",
#         "double"
#       ],
#       "default": null
#     },
#     {
#       "name": "Longitude",
#       "type": [
#         "null",
#         "double"
#       ],
#       "default": null
#     },
#     {
#       "name": "GeocodeAccuracy",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Address",
#       "type": [
#         "null",
#         {
#           "type": "record",
#           "name": "Address",
#           "namespace": "salesforce.Address",
#           "fields": [],
#           "connect.name": "salesforce.Address.Address"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "Phone",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "MobilePhone",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Fax",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Email",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Website",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "PhotoUrl",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Description",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "LeadSource",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Status",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Industry",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Rating",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "AnnualRevenue",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "NumberOfEmployees",
#       "type": [
#         "null",
#         "int"
#       ],
#       "default": null
#     },
#     {
#       "name": "OwnerId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "IsConverted",
#       "type": [
#         "null",
#         "boolean"
#       ],
#       "default": null
#     },
#     {
#       "name": "ConvertedDate",
#       "type": [
#         "null",
#         {
#           "type": "int",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Date",
#           "logicalType": "date"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "ConvertedAccountId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "ConvertedContactId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "ConvertedOpportunityId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "IsUnreadByOwner",
#       "type": [
#         "null",
#         "boolean"
#       ],
#       "default": null
#     },
#     {
#       "name": "CreatedDate",
#       "type": [
#         "null",
#         {
#           "type": "long",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Timestamp",
#           "logicalType": "timestamp-millis"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "CreatedById",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "LastModifiedDate",
#       "type": [
#         "null",
#         {
#           "type": "long",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Timestamp",
#           "logicalType": "timestamp-millis"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "LastModifiedById",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "SystemModstamp",
#       "type": [
#         "null",
#         {
#           "type": "long",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Timestamp",
#           "logicalType": "timestamp-millis"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "LastActivityDate",
#       "type": [
#         "null",
#         {
#           "type": "int",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Date",
#           "logicalType": "date"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "LastViewedDate",
#       "type": [
#         "null",
#         {
#           "type": "long",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Timestamp",
#           "logicalType": "timestamp-millis"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "LastReferencedDate",
#       "type": [
#         "null",
#         {
#           "type": "long",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Timestamp",
#           "logicalType": "timestamp-millis"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "Jigsaw",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "JigsawContactId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "CleanStatus",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "CompanyDunsNumber",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "DandbCompanyId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "EmailBouncedReason",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "EmailBouncedDate",
#       "type": [
#         "null",
#         {
#           "type": "long",
#           "connect.version": 1,
#           "connect.name": "org.apache.kafka.connect.data.Timestamp",
#           "logicalType": "timestamp-millis"
#         }
#       ],
#       "default": null
#     },
#     {
#       "name": "IndividualId",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "IsPriorityRecord",
#       "type": [
#         "null",
#         "boolean"
#       ],
#       "default": null
#     },
#     {
#       "name": "SICCode__c",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "ProductInterest__c",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "Primary__c",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "CurrentGenerators__c",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     },
#     {
#       "name": "NumberofLocations__c",
#       "type": [
#         "null",
#         "double"
#       ],
#       "default": null
#     },
#     {
#       "name": "CustomId__c",
#       "type": [
#         "null",
#         "string"
#       ],
#       "default": null
#     }
#   ],
#   "connect.name": "io.confluent.salesforce.Lead"
# }
# CreateTime:2026-06-09 11:09:45.101|Partition:0|Offset:0|Headers:source.system:salesforce,source.entity:Lead,source.operation:INSERT,source.loading.mode:Event-Driven Sync,source.connector:salesforce-source-v2,source.task:2364315,source.transaction.key:0003c81d-9cdf-a681-7a68-dd7b564772b5,source.sequence.number:1,source.commit.timestamp:1780996181000|Key:{"Id":"00QKB000002vPqN2AU"}|Value:{"Id":"00QKB000002vPqN2AU","IsDeleted":null,"MasterRecordId":null,"LastName":null,"FirstName":null,"Salutation":null,"Name":{"string":"{\"Salutation\": null, \"FirstName\": \"John_2445\", \"LastName\": \"Doe_12848\"}"},"Title":null,"Company":{"string":"Confluent"},"Street":null,"City":null,"State":null,"PostalCode":null,"Country":null,"Latitude":null,"Longitude":null,"GeocodeAccuracy":null,"Address":null,"Phone":null,"MobilePhone":null,"Fax":null,"Email":null,"Website":null,"PhotoUrl":null,"Description":null,"LeadSource":null,"Status":{"string":"Open - Not Contacted"},"Industry":null,"Rating":null,"AnnualRevenue":null,"NumberOfEmployees":null,"OwnerId":{"string":"0052X00000AJGNCQA5"},"IsConverted":{"boolean":false},"ConvertedDate":null,"ConvertedAccountId":null,"ConvertedContactId":null,"ConvertedOpportunityId":null,"IsUnreadByOwner":{"boolean":true},"CreatedDate":{"long":1780996181000},"CreatedById":{"string":"0052X00000AJGNCQA5"},"LastModifiedDate":{"long":1780996181000},"LastModifiedById":{"string":"0052X00000AJGNCQA5"},"SystemModstamp":null,"LastActivityDate":null,"LastViewedDate":null,"LastReferencedDate":null,"Jigsaw":null,"JigsawContactId":null,"CleanStatus":{"string":"Pending"},"CompanyDunsNumber":null,"DandbCompanyId":null,"EmailBouncedReason":null,"EmailBouncedDate":null,"IndividualId":null,"IsPriorityRecord":null,"SICCode__c":null,"ProductInterest__c":null,"Primary__c":null,"CurrentGenerators__c":null,"NumberofLocations__c":null,"CustomId__c":null}|ValueSchemaId:100106