# Salesforce SObject Sink connector



## Objective

Quickly test [Salesforce SObject Sink](https://docs.confluent.io/current/connect/kafka-connect-salesforce/sobjects_sink/index.html#salesforce-sobject-sink-connector-for-cp) connector.


## Register a test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Register another test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Salesforce Account

### Create a new Connected App

Full details available [here](https://docs.confluent.io/current/connect/kafka-connect-salesforce/pushtopics/salesforce_pushtopic_source_connector_quickstart.html#salesforce-account)

Steps are:

* Select the gear icon in the upper right hand corner and choose Setup.

* Enter App in the Quick Find search box, and choose *App Manager* in the filtered results.

* Click the *New Connected App* button in the upper right corner of the Setup panel.

![Create a connected app](Screenshot2.png)

* Supply a Connected App Name, API Name, and Contact Email.

* Select *Enable OAuth Settings* checkbox and select the *Enable for Device Flow* checkbox. These selections enable the connector to use the Salesforce API.
* Under the *Select OAuth Scopes* field, select all of the items under Available OAuth scopes and add them to the *Selected OAuth Scopes*.

Example:

![Create a connected app](Screenshot3.png)

* Save the new app and press Continue at the prompt.
* Look for the Consumer Key and Consumer Secret in the displayed form. Save these so you can put them in the configuration properties file for the Salesforce connect worker.

### Find your Security token

Find your Security Token (emailed to you from Salesforce.com). If you need to reset your token or view your profile on Salesforce.com, select `Settings->My Personal Information->Reset My Security Token` and follow the instructions.

![security token](Screenshot1.png)

## Create CustomId External ID

Follow instructions [here](https://docs.confluent.io/current/connect/kafka-connect-salesforce/sobjects_sink/index.html#external-id), **for both accounts**.

![custom PushTopic](Screenshot4.png)

## How to run

Simply run:

```
$ ./salesforce-sobject-sink.sh <SALESFORCE_USERNAME> <SALESFORCE_PASSWORD> <SALESFORCE_CONSUMER_KEY> <SALESFORCE_CONSUMER_PASSWORD> <SALESFORCE_SECURITY_TOKEN> <SALESFORCE_USERNAME_ACCOUNT2> <SALESFORCE_PASSWORD_ACCOUNT2> <SALESFORCE_SECURITY_TOKEN_ACCOUNT2> <SALESFORCE_CONSUMER_KEY_ACCOUNT2> <SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2>
```

Note: you can also export these values as environment variable


## Details of what the script is doing

The Salesforce PushTopic source connector is used to get data into Kafka and the Salesforce SObject sink connector is used to export data from Kafka to Salesforce

Login with sfdx CLI

```bash
$ docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""
```

Delete MyLeadPushTopics, if required

```bash
$ docker exec -i sfdx-cli sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic WHERE Name = 'MyLeadPushTopics'];
Database.delete(pts);
EOF
```

Create MyLeadPushTopics

```bash
$ docker exec sfdx-cli sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\" -f \"/tmp/MyLeadPushTopics.apex\""
```

Add a Lead to Salesforce

```bash
$ docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""
```

Creating Salesforce PushTopics Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
                    "kafka.topic": "sfdc-pushtopic-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.push.topic.name" : "MyLeadPushTopics",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SALESFORCE_SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$SALESFORCE_CONSUMER_KEY"'",
                    "salesforce.consumer.secret" : "'"$SALESFORCE_CONSUMER_PASSWORD"'",
                    "salesforce.initial.start" : "latest",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-pushtopic-source/config | jq .
```

Verify we have received the data in `sfdc-pushtopic-leads` topic

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-pushtopic-leads --from-beginning --max-messages 1
```

Creating Salesforce SObject Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforceSObjectSinkConnector",
                    "topics": "sfdc-pushtopic-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE_ACCOUNT2"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME_ACCOUNT2"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD_ACCOUNT2"'",
                    "salesforce.password.token" : "'"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2"'",
                    "salesforce.consumer.key" : "'"$SALESFORCE_CONSUMER_KEY_ACCOUNT2"'",
                    "salesforce.consumer.secret" : "'"$SALESFORCE_CONSUMER_PASSWORD_ACCOUNT2"'",
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
          }' \
     http://localhost:8083/connectors/salesforce-sobject-sink/config | jq .
````

Verify topic `success-responses`

```bash
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 1
```

Results:

```
"Successfully delivered the record to salesforce"
```


Login with sfdx CLI on the account #2

```bash
$ docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\""
```

Get the Lead created on account #2

```bash
docker exec sfdx-cli sh -c "sfdx force:data:record:get  -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -w \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""
```

Results:

```
attributes:
  type: "Lead"
  url: "/services/data/v49.0/sobjects/Lead/00Q2X00001OUd8RUAT"
Id: "00Q7R00001OtXTRUA3"
IsDeleted: null
MasterRecordId: null
LastName: "Doe_18021"
FirstName: "John_28862"
Salutation: null
Name: "John_28862 Doe_18021"
Title: null
Company: "Confluent"
Street: null
City: null
State: null
PostalCode: null
Country: null
Latitude: null
Longitude: null
GeocodeAccuracy: null
Address: null
Phone: null
MobilePhone: null
Fax: null
Email: null
Website: null
PhotoUrl: "/services/images/photo/00Q7R00001OtXTRUA3"
Description: null
LeadSource: "Website Capture"
Status: "Unassigned"
Industry: null
Rating: null
AnnualRevenue: null
NumberOfEmployees: null
OwnerId: "0052X00000ANeP4QAL"
IsConverted: null
ConvertedDate: null
ConvertedAccountId: null
ConvertedContactId: null
ConvertedOpportunityId: null
IsUnreadByOwner: null
CreatedDate: "2020-09-21T14:42:40.000+0000"
CreatedById: "0052X00000ANeP4QAL"
LastModifiedDate: "2020-09-21T14:42:40.000+0000"
LastModifiedById: "0052X00000ANeP4QAL"
SystemModstamp: "2020-09-21T14:42:40.000+0000"
LastActivityDate: null
LastViewedDate: "2020-09-21T14:42:51.000+0000"
LastReferencedDate: "2020-09-21T14:42:51.000+0000"
Jigsaw: null
JigsawContactId: null
CleanStatus: "Pending"
CompanyDunsNumber: null
DandbCompanyId: null
EmailBouncedReason: null
EmailBouncedDate: null
IndividualId: null
SICCode__c: null
ProductInterest__c: null
Primary__c: null
CurrentGenerators__c: null
NumberofLocations__c: null
CustomId__c: "00Q5500000B2zFDEAZ"
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
