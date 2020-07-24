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



N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
