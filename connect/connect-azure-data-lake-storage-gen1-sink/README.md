# Azure Data Lake Storage Gen1 Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-azure-data-lake-storage-gen1-sink/asciinema.gif?raw=true)

## Objective

Quickly test [Azure Data Lake Storage Gen1 Sink](https://docs.confluent.io/current/connect/kafka-connect-azure-data-lake-gen1-storage/index.html#quick-start) connector.


## How to run

Simply run:

```
$ ./azure-data-lake-storage-gen1.sh
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
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
```

Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP

```bash
$ az dls account create --account $AZURE_DATALAKE_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP
```

Giving permission to app $AZURE_AD_APP_NAME to get access to data lake $AZURE_DATALAKE_ACCOUNT_NAME

```bash
$ az dls fs access set-entry --account $AZURE_DATALAKE_ACCOUNT_NAME  --acl-spec user:$SERVICE_PRINCIPAL_ID:rwx --path /
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.datalake.gen1.AzureDataLakeGen1StorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "datalake_topic",
                    "flush.size": "3",
                    "azure.datalake.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.client.key": "mypassword",
                    "azure.datalake.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-datalake-gen1-sink/config | jq .
```

Sending messages to topic datalake_topic

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Listing ${AZURE_DATALAKE_CLIENT_KEY} in Azure Blob Storage

```bash
$ az dls fs list --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --path /topics
```

Getting one of the avro files locally and displaying content with avro-tools

```bash
$ az dls fs download --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --overwrite --source-path /topics/datalake_topic/partition=0/datalake_topic+0+0000000000.avro --destination-path /tmp/datalake_topic+0+0000000000.avro
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
