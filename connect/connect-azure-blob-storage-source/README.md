# Azure Blob Storage Source connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Azure Blob Storage Source](https://docs.confluent.io/current/connect/kafka-connect-azure-blob-storage/source/index.html#az-blob-storage-source-connector-for-cp) connector.


## How to run

Simply run:

```
$ ./azure-blob-storage-source.sh
```

## Details of what the script is doing

Steps from [connect-azure-blob-storage-sink](connect/connect-azure-blob-storage-sink/README.md)


Creating Azure Blob Storage Source connector

```bash
$ docker exec -e AZURE_ACCOUNT_NAME="$AZURE_ACCOUNT_NAME" -e AZURE_ACCOUNT_KEY="$AZURE_ACCOUNT_KEY" -e AZURE_CONTAINER_NAME="$AZURE_CONTAINER_NAME" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
                "tasks.max": "1",
                "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                "format.class": "io.confluent.connect.azure.blob.storage.format.avro.AvroFormat",
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
$ timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic copy_of_blob_topic --from-beginning --max-messages 3
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
