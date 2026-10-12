# Azure Data Explorer (Kusto) Sink connector



## Objective

Quickly test [Azure Data Explorer (Kusto) Sink](https://github.com/Azure/kafka-sink-azure-kusto) connector.

The connector requires JDK 17, so the example is skipped with CP versions older than 7.7.0.

## Prerequisites

The script creates everything that is needed:

* an Azure Data Explorer cluster (`Dev(No SLA)_Standard_E2a_v4` SKU, creation takes around 15 minutes) and a database
* a table `kusto_topic`, a JSON ingestion mapping `kusto_topic_json_mapping` and an ingestion batching policy of 10 seconds (default is 5 minutes)
* an Entra app/service principal with `Database Ingestor` and `Database Viewer` roles on the database (when running in CI, the pre-created service principal `AZURE_LOGS_CLIENT_ID`/`AZURE_LOGS_CLIENT_SECRET` is used instead)

It then sends 10 Avro records to topic `kusto_topic`, creates the sink connector (queued ingestion, JSON format) and waits until the 10 rows are in the table.

The resource group and the Entra app are deleted at the end of the run.

## How to run

Simply run:

```
$ just use <playground run> command and search for azure-data-explorer-kusto-sink.sh in this folder
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).
