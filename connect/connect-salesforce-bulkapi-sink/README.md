# Salesforce Bulk API Sink connector


## Objective

Quickly test [Salesforce Bulk API Sink](https://docs.confluent.io/current/connect/kafka-connect-salesforce-bulk-api/sink/index.html#salesforce-bulk-api-sink-connector-for-cp) connector.


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


## How to run

Simply run:

```
$ ./salesforce-bukapi-sink.sh <SALESFORCE_USERNAME> <SALESFORCE_PASSWORD> <CONSUMER_KEY> <CONSUMER_PASSWORD> <SECURITY_TOKEN> <SALESFORCE_USERNAME_ACCOUNT2> <SALESFORCE_PASSWORD_ACCOUNT2> <SECURITY_TOKEN_ACCOUNT2>
```

Note: you can also export these values as environment variable


## Details of what the script is doing

The Salesforce PushTopic source connector is used to get data into Kafka and the Salesforce Bulk API sink connector is used to export data from Kafka to Salesforce

Login with sfdx CLI

```bash
$ docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"https://login.salesforce.com\" -s \"$SECURITY_TOKEN\""
```

Add a Lead to Salesforce

```bash
$ docker exec sfdx-cli sh -c "sfdx force:data:record:create  -u \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='John_$RANDOM' LastName='Doe_$RANDOM' Company=Confluent\""
```

Creating Salesforce PushTopics Source connector

```bash
$ docker exec -e SALESFORCE_USERNAME="$SALESFORCE_USERNAME" -e SALESFORCE_PASSWORD="$SALESFORCE_PASSWORD" -e CONSUMER_KEY="$CONSUMER_KEY" -e CONSUMER_PASSWORD="$CONSUMER_PASSWORD" -e SECURITY_TOKEN="$SECURITY_TOKEN" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
                    "kafka.topic": "sfdc-pushtopic-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.push.topic.name" : "MyCustomLeadsPushTopic",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY"'",
                    "salesforce.consumer.secret" : "'"$CONSUMER_PASSWORD"'",
                    "salesforce.initial.start" : "all",
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

Creating Salesforce Bulk API Sink connector

```bash
$ docker exec -e SALESFORCE_USERNAME_ACCOUNT2="$SALESFORCE_USERNAME_ACCOUNT2" -e SALESFORCE_PASSWORD_ACCOUNT2="$SALESFORCE_PASSWORD_ACCOUNT2" -e SECURITY_TOKEN_ACCOUNT2="$SECURITY_TOKEN_ACCOUNT2" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSinkConnector",
                    "topics": "sfdc-pushtopic-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME_ACCOUNT2"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD_ACCOUNT2"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN_ACCOUNT2"'",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-sink/config | jq .
````

Verify topic `success-responses`

```bash
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 1
```

```
"{Id: 00Q2X00001OUcZgUAL ,Success: true ,Created: true}"
Processed a total of 1 messages
```

Login to your SFDC account for account #2 to check that Lead has been added

```bash

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
