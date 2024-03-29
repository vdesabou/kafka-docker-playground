# Azure Data Lake Storage Gen2 Sink connector



## Objective

Quickly test [Azure Data Lake Storage Gen2 Sink](https://docs.confluent.io/current/connect/kafka-connect-azure-data-lake-gen2-storage/index.html#quick-start) connector.



## How to run

Simply run:

```
$ just use <playground run> command and search for azure-data-lake-storage-gen2-sink.sh in this folder
```

Or using 2 way SSL authentication:

```bash
$ just use <playground run> command and search for azure-data-lake-storage-gen2-2way-ssl.sh in this folder
```

**Note**: You need to provide the tenant name by providing AZURE_SUBSCRIPTION_NAME environment variable. Check the list of tenants using `az account list`.

Note if you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) make sure to set `AZURE_SUBSCRIPTION_NAME` environment variable to create Azure resource group in correct subscription (for confluent support, subscription is `COPS`).