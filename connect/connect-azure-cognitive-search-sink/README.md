# Azure Cognitive Search Sink connector



## Objective

Quickly test [Azure Cognitive Search Sink](https://docs.confluent.io/kafka-connect-azure-search/current/overview.html#az-cognitive-search-sink-connector-for-cp) connector.




## How to run

Simply run:

```
$ just use <playground run> command and search for azure-cognitive-search.sh in this folder
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).