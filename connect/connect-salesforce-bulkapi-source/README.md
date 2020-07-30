# Salesforce Bulk API Source connector


## Objective

Quickly test [Salesforce Bulk API Source](https://docs.confluent.io/current/connect/kafka-connect-salesforce-bulk-api/source/index.html#quick-start) connector.



## Register a test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Follow instructions to create a Connected App

[Link](https://docs.confluent.io/current/connect/kafka-connect-salesforce/bukapis/salesforce_bukapi_source_connector_quickstart.html#salesforce-account)

## How to run

Simply run:

```
$ ./salesforce-bukapi-source.sh <SALESFORCE_USERNAME> <SALESFORCE_PASSWORD> <SECURITY_TOKEN>
```

Note: you can also export these values as environment variable

<SECURITY_TOKEN>: you can get it from `Settings->My Personal Information->Reset My Security Token`:

![security token](Screenshot1.png)


## Details of what the script is doing

Login with sfdx CLI

```bash
$ docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"https://login.salesforce.com\" -s \"$SECURITY_TOKEN\""
```

Add a Lead to Salesforce

```bash
$ docker exec sfdx-cli sh -c "sfdx force:data:record:create  -u \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='John_$RANDOM' LastName='Doe_$RANDOM' Company=Confluent\""
```

Creating Salesforce Bulk API Source connector

```bash
$ docker exec -e SALESFORCE_USERNAME="$SALESFORCE_USERNAME" -e SALESFORCE_PASSWORD="$SALESFORCE_PASSWORD" -e SECURITY_TOKEN="$SECURITY_TOKEN" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSourceConnector",
                    "kafka.topic": "sfdc-bulkapi-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-source/config | jq .
```


Verify we have received the data in `sfdc-bukapi-leads` topic

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-bukapi-leads --from-beginning --max-messages 1
```

Results:

```json
{
    "payload": {
        "AnnualRevenue": null,
        "City": null,
        "CleanStatus": "Pending",
        "Company": "cdscsdcsdcsd",
        "CompanyDunsNumber": null,
        "ConvertedAccountId": null,
        "ConvertedContactId": null,
        "ConvertedDate": null,
        "ConvertedOpportunityId": null,
        "Country": null,
        "CreatedById": "0052X00000AJGNCQA5",
        "CreatedDate": 1595578138000,
        "CurrentGenerators__c": null,
        "DandbCompanyId": null,
        "Description": null,
        "Email": "csdcsd@titi.com",
        "EmailBouncedDate": null,
        "EmailBouncedReason": null,
        "Fax": null,
        "FirstName": "csdcds",
        "GeocodeAccuracy": null,
        "Id": "00Q2X00001OPBbQUAX",
        "IndividualId": null,
        "Industry": null,
        "IsConverted": false,
        "IsDeleted": false,
        "IsUnreadByOwner": true,
        "Jigsaw": null,
        "JigsawContactId": null,
        "LastActivityDate": null,
        "LastModifiedById": "0052X00000AJGNCQA5",
        "LastModifiedDate": 1595578138000,
        "LastName": "csdcsd",
        "LastReferencedDate": 1595578138000,
        "LastViewedDate": 1595578138000,
        "Latitude": null,
        "LeadSource": null,
        "Longitude": null,
        "MasterRecordId": null,
        "MobilePhone": null,
        "Name": "csdcds csdcsd",
        "NumberOfEmployees": null,
        "NumberofLocations__c": null,
        "OwnerId": "0052X00000AJGNCQA5",
        "Phone": null,
        "PhotoUrl": "/services/images/photo/00Q2X00001OPBbQUAX",
        "PostalCode": null,
        "Primary__c": null,
        "ProductInterest__c": null,
        "Rating": null,
        "SICCode__c": null,
        "Salutation": "Mr.",
        "State": null,
        "Status": "Open - Not Contacted",
        "Street": null,
        "SystemModstamp": 1595578138000,
        "Title": "cdcs",
        "Website": null
    },
    "schema": {
        "fields": [
            {
                "field": "Id",
                "optional": false,
                "type": "string"
            },
            {
                "field": "IsDeleted",
                "optional": true,
                "type": "boolean"
            },
            {
                "field": "MasterRecordId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "LastName",
                "optional": true,
                "type": "string"
            },
            {
                "field": "FirstName",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Salutation",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Name",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Title",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Company",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Street",
                "optional": true,
                "type": "string"
            },
            {
                "field": "City",
                "optional": true,
                "type": "string"
            },
            {
                "field": "State",
                "optional": true,
                "type": "string"
            },
            {
                "field": "PostalCode",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Country",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Latitude",
                "optional": true,
                "type": "double"
            },
            {
                "field": "Longitude",
                "optional": true,
                "type": "double"
            },
            {
                "field": "GeocodeAccuracy",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Phone",
                "optional": true,
                "type": "string"
            },
            {
                "field": "MobilePhone",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Fax",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Email",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Website",
                "optional": true,
                "type": "string"
            },
            {
                "field": "PhotoUrl",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Description",
                "optional": true,
                "type": "string"
            },
            {
                "field": "LeadSource",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Status",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Industry",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Rating",
                "optional": true,
                "type": "string"
            },
            {
                "field": "AnnualRevenue",
                "optional": true,
                "type": "string"
            },
            {
                "field": "NumberOfEmployees",
                "optional": true,
                "type": "int32"
            },
            {
                "field": "OwnerId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "IsConverted",
                "optional": true,
                "type": "boolean"
            },
            {
                "field": "ConvertedDate",
                "name": "org.apache.kafka.connect.data.Date",
                "optional": true,
                "type": "int32",
                "version": 1
            },
            {
                "field": "ConvertedAccountId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "ConvertedContactId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "ConvertedOpportunityId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "IsUnreadByOwner",
                "optional": true,
                "type": "boolean"
            },
            {
                "field": "CreatedDate",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "CreatedById",
                "optional": true,
                "type": "string"
            },
            {
                "field": "LastModifiedDate",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "LastModifiedById",
                "optional": true,
                "type": "string"
            },
            {
                "field": "SystemModstamp",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "LastActivityDate",
                "name": "org.apache.kafka.connect.data.Date",
                "optional": true,
                "type": "int32",
                "version": 1
            },
            {
                "field": "LastViewedDate",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "LastReferencedDate",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "Jigsaw",
                "optional": true,
                "type": "string"
            },
            {
                "field": "JigsawContactId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "CleanStatus",
                "optional": true,
                "type": "string"
            },
            {
                "field": "CompanyDunsNumber",
                "optional": true,
                "type": "string"
            },
            {
                "field": "DandbCompanyId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "EmailBouncedReason",
                "optional": true,
                "type": "string"
            },
            {
                "field": "EmailBouncedDate",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "IndividualId",
                "optional": true,
                "type": "string"
            },
            {
                "field": "SICCode__c",
                "optional": true,
                "type": "string"
            },
            {
                "field": "ProductInterest__c",
                "optional": true,
                "type": "string"
            },
            {
                "field": "Primary__c",
                "optional": true,
                "type": "string"
            },
            {
                "field": "CurrentGenerators__c",
                "optional": true,
                "type": "string"
            },
            {
                "field": "NumberofLocations__c",
                "optional": true,
                "type": "double"
            }
        ],
        "optional": false,
        "type": "struct"
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
