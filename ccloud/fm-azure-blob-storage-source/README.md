# Fully Managed Azure Blob Storage Source connector

## Objective

Quickly test the [Fully Managed Azure Blob Storage Source](https://docs.confluent.io/cloud/current/connectors/cc-azure-blob-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure: the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) logs in with `az login` (browser), or with a service principal when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. If you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription), subscription in which the Azure resource group is created (for Confluent support, subscription is `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`). The Confluent Cloud cluster is expected on Azure in this region |

## How to run

```bash
playground run -f fully-managed-azure-blob-storage-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-blob-storage-source.sh` | Azure Blob Storage Source connector (generalized mode) reading a JSON file |

## What the script does

1. Recreates an Azure resource group, then creates a storage account and a container (all named `pg<USER>fmbs<TAG_BASE>`, truncated to 24 characters).
2. Bootstraps the Confluent Cloud environment.
3. Uploads `generalized.quickstart.json` (9 JSON records) to `quickstart/` in the container.
4. Creates the fully managed connector `AzureBlobSource_<USER>` (JSON input and output, `topic.regex.list=quick-start-topic:.*`) and waits for it to be running.
5. Verifies that `quick-start-topic` contains 9 records with `playground topic consume`.
6. Asks for confirmation before deleting the connector, then (on exit) before deleting the resource group.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-azure-blob-storage-source`](../../connect/connect-azure-blob-storage-source/README.md#benchmark): it loads JSON files in the Azure Blob Storage container (the account key is read with `az storage account keys list`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
