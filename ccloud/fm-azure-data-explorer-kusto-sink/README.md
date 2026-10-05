# Fully Managed Azure Data Explorer (Kusto) Database Sink connector



## Objective

Quickly test [Fully Managed Azure Data Explorer (Kusto) Database Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-data-explorer-kusto-sink.html) connector.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

The script creates everything that is needed:

* an Azure Data Explorer cluster (`Dev(No SLA)_Standard_E2a_v4` SKU, creation takes around 15 minutes) and a database
* a table `kusto_topic`, a JSON ingestion mapping `kusto_topic_json_mapping` and an ingestion batching policy of 10 seconds (default is 5 minutes)
* an Entra app/service principal with `Database Ingestor` and `Database Viewer` roles on the database (when running in CI, the pre-created service principal `AZURE_LOGS_CLIENT_ID`/`AZURE_LOGS_CLIENT_SECRET` is used instead)

The resource group and the Entra app are deleted at the end of the run.

## How to run

Simply run:

```
$ just use <playground run> command
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).
