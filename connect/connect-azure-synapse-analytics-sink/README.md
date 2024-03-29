# Azure Synapse Analytics Sink connector



## Objective

Quickly test [Azure Synapse Analytics Sink](https://docs.confluent.io/kafka-connectors/azure-sql-dw/current/overview.html) connector.


## How to run

Simply run:

```
$ just use <playground run> command and search for azure-synapse-analytics-sink.sh in this folder
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).