# Salesforce Bulk API Sink connector


## Objective

Quickly test [Salesforce Bulk API Sink](https://docs.confluent.io/current/connect/kafka-connect-salesforce-bulk-api/sink/index.html#salesforce-bulk-api-sink-connector-for-cp) connector.


## Register a test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Register another test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Follow instructions to create a Connected App

[Link](https://docs.confluent.io/current/connect/kafka-connect-salesforce/bukapis/salesforce_bukapi_source_connector_quickstart.html#salesforce-account)

## Add a Lead to Salesforce

[Link](https://docs.confluent.io/current/connect/kafka-connect-salesforce/bukapis/salesforce_bukapi_source_connector_quickstart.html#add-a-lead-to-salesforce)

## How to run

Simply run:

```
$ ./salesforce-bukapi-sink.sh <SALESFORCE_USERNAME> <SALESFORCE_PASSWORD> <CONSUMER_KEY> <CONSUMER_PASSWORD> <SECURITY_TOKEN> <SALESFORCE_USERNAME_ACCOUNT2> <SALESFORCE_PASSWORD_ACCOUNT2> <SECURITY_TOKEN_ACCOUNT2>
```

Note: you can also export these values as environment variable

<SECURITY_TOKEN>: you can get it from `Settings->My Personal Information->Reset My Security Token`:

![security token](Screenshot1.png)


## Details of what the script is doing

The Salesforce PushTopic source connector is used to get data into Kafka and the Salesforce Bulk API sink connector is used to export data from Kafka to Salesforce

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
                    "salesforce.push.topic.name" : "LeadsPushTopic",
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

Verify topic `error-responses`

```bash
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1
```

**FIXTHIS**: Salesforce Bulk API sink is broken [#42](https://github.com/vdesabou/kafka-docker-playground/issues/42)

```
"[{message:Clean Status: bad value for restricted picklist field: 5, fields:[CleanStatus], code:INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST}]"
"[{message:Clean Status: bad value for restricted picklist field: 5, fields:[CleanStatus], code:INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
"[{message:invalid cross reference id, fields:[], code:INVALID_CROSS_REFERENCE_KEY}]"
```

Login to your SFDC account for account #2 to check that Lead has been added

```bash

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
