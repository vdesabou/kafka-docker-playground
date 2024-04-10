# Fully Managed Azure Cosmos DB Source connector



## Objective

Quickly test [Fully Managed Azure Cosmos DB Source](https://docs.confluent.io/cloud/current/connectors/cc-azure-cosmos-source.html) connector.


## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)


## How to run

Simply run:

```
$ just use <playground run> command
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).