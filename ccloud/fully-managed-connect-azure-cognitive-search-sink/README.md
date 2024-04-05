# Fully Managed Azure Cognitive Search Sink connector



## Objective

Quickly test [Fully Managed Azure Cognitive Search Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-cognitive-search-sink.html) connector.




## How to run

Simply run:

```
$ just use <playground run> command
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).