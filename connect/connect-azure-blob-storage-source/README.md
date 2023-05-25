# Azure Blob Storage Source connector



## Objective

Quickly test [Azure Blob Storage Source](https://docs.confluent.io/current/connect/kafka-connect-azure-blob-storage/source/index.html#az-blob-storage-source-connector-for-cp) connector.


## How to run

Simply run:

```
$ playground run -f azure-blob-storage-source-backup-and-restore<tab>
```

Simply run:

For [Backup and Restore Azure Blob Storage Source](https://docs.confluent.io/kafka-connect-azure-blob-storage-source/current/backup-and-restore/index.html):

```bash
$ playground run -f azure-blob-storage-source-backup-and-restore<tab>
```

For [Generalized Azure Blob Storage Source](https://docs.confluent.io/kafka-connect-azure-blob-storage-source/current/generalized/overview.html#) (it requires version 2.2.0 at minimum):

```bash
$ playground run -f azure-blob-storage-source-generalized<tab>
```

## Details of what the script is doing

### Backup and Restore Azure Blob Storage Source 

Steps from [connect-azure-blob-storage-sink](connect/connect-azure-blob-storage-sink/README.md)


Creating Azure Blob Storage Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
                "tasks.max": "1",
                "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                "format.class": "io.confluent.connect.cloud.storage.source.format.CloudStorageAvroFormat",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1",
                "transforms" : "AddPrefix",
                "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
                "transforms.AddPrefix.regex" : ".*",
                "transforms.AddPrefix.replacement" : "copy_of_$0"
          }' \
     http://localhost:8083/connectors/azure-blob-source/config | jq .
```

Verifying topic copy_of_blob_topic

```bash
playground topic consume --topic copy_of_blob_topic --min-expected-messages 3 --timeout 60
```


### GeneralizedAzure Blob Storage Source

Copy generalized.quickstart.json to container $AZURE_CONTAINER_NAME quickstart/generalized.quickstart.json

```bash
cp generalized.quickstart.json /tmp/
az storage blob upload --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name quickstart/generalized.quickstart.json --file /tmp/generalized.quickstart.json
```

Creating Generalized Azure Blob Storage Source connector:

```
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
                "tasks.max": "1",
                "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                "format.class": "io.confluent.connect.azure.blob.storage.format.json.JsonFormat",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "confluent.license": "",
                "mode": "GENERIC",
                "topics.dir": "quickstart",
                "topic.regex.list": "quick-start-topic:.*",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-blob-source/config | jq .
```

Verifying topic `quick-start-topic`:

```bash
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
{"f1":"value4"}
{"f1":"value5"}
{"f1":"value6"}
{"f1":"value7"}
{"f1":"value8"}
{"f1":"value9"}
Processed a total of 9 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
