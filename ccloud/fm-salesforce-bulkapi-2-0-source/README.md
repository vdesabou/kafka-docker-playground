# Fully Managed Salesforce Bulk API 2.0 Source connector



## Objective

Quickly test [Fully Managed Salesforce Bulk API 2;0 Source](https://docs.confluent.io/cloud/current/connectors/cc-salesforce-bulk-api-v2-source.html) connector.



## Register a test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Follow instructions to create a Connected App

[Link](https://docs.confluent.io/current/connect/kafka-connect-salesforce/bukapis/salesforce_bukapi_source_connector_quickstart.html#salesforce-account)

## How to run

Simply run:

```
$ just use <playground run> command and search for salesforce-bukapi-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <SALESFORCE_USERNAME> <SALESFORCE_PASSWORD> .sh in this folder
```

Note: you can also export these values as environment variable

<SALESFORCE_SECURITY_TOKEN>: you can get it from `Settings->My Personal Information->Reset My Security Token`:

![security token](Screenshot1.png)


## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)