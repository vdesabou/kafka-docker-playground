# Azure Data Lake Storage Gen2 Sink connector

## Objective

Quickly test [Azure Data Lake Storage Gen2 Sink](https://docs.confluent.io/current/connect/kafka-connect-azure-data-lake-gen2-storage/index.html#quick-start) connector.
## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* `avro-tools` (example `brew install avro-tools`)
* `az`(example `brew install azure-cli`)

## How to run

Simply run:

```
$ ./azure-data-lake-storage-gen2.sh
```

## Details of what the script is doing

Logging to Azure using browser

```bash
az login
```

Add the CLI extension for Azure Data Lake Gen 2

```bash
$ az extension add --name storage-preview
```

Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION

```bash
$ az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
```

Registering active directory App $AZURE_AD_APP_NAME

```bash
$ AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --password mypassword --native-app false --available-to-other-tenants false --query appId -o tsv)
```

Creating Service Principal associated to the App

```bash
$ SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.objectId')
$ AZURE_TENANT_ID=$(az account list | jq -r '.[].tenantId')
$ AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"
```

Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP

```bash
$ az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true
```

Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID

```bash
$ az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner"
```

The connector is created with:

```bash
$ docker exec -e AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID" -e AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME" -e AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "azure-datalake-gen2-sink",
               "config": {
                    "connector.class": "io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector",
                    "tasks.max": "1",
                    "topics": "datalake_topic",
                    "flush.size": "3",
                    "azure.datalake.gen2.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.gen2.client.key": "mypassword",
                    "azure.datalake.gen2.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.gen2.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .
```

Sending messages to topic datalake_topic

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Listing ${AZURE_DATALAKE_CLIENT_KEY} in Azure Blob Storage

```bash
$ az storage blob list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --container-name topics
```

Getting one of the avro files locally and displaying content with avro-tools

```bash
$ az storage blob download  --container-name topics --name datalake_topic/partition=0/datalake_topic+0+0000000000.avro --file /tmp/datalake_topic+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
