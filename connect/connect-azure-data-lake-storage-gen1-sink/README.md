# Azure Data Lake Storage Gen1 Sink connector

## Objective

Quickly test [Azure Data Lake Storage Gen1 Sink](https://docs.confluent.io/current/connect/kafka-connect-azure-data-lake-gen1-storage/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* `avro-tools` (example `brew install avro-tools`)
* `az`(example `brew install azure-cli`)

## Azure Setup

* [Create a Data Lake Storage Gen1 account](https://docs.microsoft.com/en-us/azure/data-lake-store/data-lake-store-get-started-portal#create-a-data-lake-storage-gen1-account). For `Encryption Seetings`, use `Use keys managed by Data Lake Storage Gen1`

* Follow [Service-to-service authentication with Azure Data Lake Storage Gen1 using Azure Active Directory](https://docs.microsoft.com/en-us/azure/data-lake-store/data-lake-store-service-to-service-authenticate-using-active-directory)


## How to run

Simply run:

```
$ ./azure-data-lake-storage-gen1.sh <AZURE_DATALAKE_CLIENT_ID> <AZURE_DATALAKE_CLIENT_KEY> <AZURE_DATALAKE_ACCOUNT_NAME> <AZURE_DATALAKE_TOKEN_ENDPOINT>
```

## Details of what the script is doing

The connector is created with:

```bash
$ docker exec -e AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID" -e AZURE_DATALAKE_CLIENT_KEY="$AZURE_DATALAKE_CLIENT_KEY" -e AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME" -e AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "azure-datalake-gen1-sink3",
               "config": {
                    "connector.class": "io.confluent.connect.azure.datalake.gen1.AzureDataLakeGen1StorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "datalake_topic",
                    "flush.size": "3",
                    "azure.datalake.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.client.key": "'"$AZURE_DATALAKE_CLIENT_KEY"'",
                    "azure.datalake.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
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
$ az dls fs list --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --path /topics
```

Getting one of the avro files locally and displaying content with avro-tools

```bash
$ az dls fs download --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --source-path /topics/datalake_topic/partition=0/datalake_topic+0+0000000000.avro --destination-path /tmp/datalake_topic+0+0000000000.avro
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
