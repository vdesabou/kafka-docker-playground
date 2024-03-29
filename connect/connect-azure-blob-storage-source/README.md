# Azure Blob Storage Source connector



## Objective

Quickly test [Azure Blob Storage Source](https://docs.confluent.io/current/connect/kafka-connect-azure-blob-storage/source/index.html#az-blob-storage-source-connector-for-cp) connector.


## How to run

Simply run:

```
$ just use <playground run> command and search for azure-blob-storage-source-backup-and-restore.sh in this folder
```

Simply run:

For [Backup and Restore Azure Blob Storage Source](https://docs.confluent.io/kafka-connect-azure-blob-storage-source/current/backup-and-restore/index.html):

```bash
$ just use <playground run> command and search for azure-blob-storage-source-backup-and-restore.sh in this folder
```

For [Generalized Azure Blob Storage Source](https://docs.confluent.io/kafka-connect-azure-blob-storage-source/current/generalized/overview.html#) (it requires version 2.2.0 at minimum):

```bash
$ just use <playground run> command and search for azure-blob-storage-source-generalized.sh in this folder
```

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).
