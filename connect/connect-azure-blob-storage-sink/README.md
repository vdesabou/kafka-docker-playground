# Azure Blob Storage Sink connector

## Objective

Quickly test [Azure Blob Storage Sink](https://docs.confluent.io/current/connect/kafka-connect-azure-blob-storage/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* `az`(example `brew install azure-cli`)

## Azure Setup

* [Create a block blob storage account](https://docs.microsoft.com/en-gb/azure/storage/blobs/storage-blob-create-account-block-blob)

## How to run

Simply run:

```
$ ./azure-blob-storage.sh <AZURE_STORAGE_ACCOUNT> <AZURE_STORAGE_KEY> [<CONTAINER_NAME>]
```

Notes:

* You can find storage account name and storage key in `Access keys` menu.
* Default for `CONTAINER_NAME`is `confluent-kafka-connect-azure-blob-storage-testing`

## Details of what the script is doing

The connector is created with:

```bash
$ docker exec -e AZURE_STORAGE_ACCOUNT="$AZURE_STORAGE_ACCOUNT" -e AZURE_STORAGE_KEY="$AZURE_STORAGE_KEY" -e CONTAINER_NAME="$CONTAINER_NAME" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "azure-blob-sink",
               "config": {
                    "connector.class": "io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "blob_topic",
                    "flush.size": "3",
                    "azblob.account.name": "'"$AZURE_STORAGE_ACCOUNT"'",
                    "azblob.account.key": "'"$AZURE_STORAGE_KEY"'",
                    "azblob.container.name": "'"$CONTAINER_NAME"'",
                    "format.class": "io.confluent.connect.azure.blob.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .
```

Messages are sent to `blob_topic` topic using:

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic blob_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Listing objects of container ${CONTAINER_NAME} in Azure Blob Storage:

```bash
$ az storage blob list --account-name "${AZURE_STORAGE_ACCOUNT}" --account-key "${AZURE_STORAGE_KEY}" --container-name "${CONTAINER_NAME}"
```

Results:

```json
[
  {
    "content": null,
    "deleted": false,
    "metadata": null,
    "name": "topics/blob_topic/partition=0/blob_topic+0+0000000000.avro",
    "properties": {
      "appendBlobCommittedBlockCount": null,
      "blobTier": "Hot",
      "blobTierChangeTime": null,
      "blobTierInferred": true,
      "blobType": "BlockBlob",
      "contentLength": 213,
      "contentRange": null,
      "contentSettings": {
        "cacheControl": null,
        "contentDisposition": null,
        "contentEncoding": null,
        "contentLanguage": null,
        "contentMd5": null,
        "contentType": "application/octet-stream"
      },
      "copy": {
        "completionTime": null,
        "id": null,
        "progress": null,
        "source": null,
        "status": null,
        "statusDescription": null
      },
      "creationTime": "2019-11-12T15:05:42+00:00",
      "deletedTime": null,
      "etag": "0x8D7678258B055E1",
      "lastModified": "2019-11-12T15:09:42+00:00",
      "lease": {
        "duration": null,
        "state": "available",
        "status": "unlocked"
      },
      "pageBlobSequenceNumber": null,
      "remainingRetentionDays": null,
      "serverEncrypted": true
    },
    "snapshot": null
  },
  {
    "content": null,
    "deleted": false,
    "metadata": null,
    "name": "topics/blob_topic/partition=0/blob_topic+0+0000000003.avro",
    "properties": {
      "appendBlobCommittedBlockCount": null,
      "blobTier": "Hot",
      "blobTierChangeTime": null,
      "blobTierInferred": true,
      "blobType": "BlockBlob",
      "contentLength": 213,
      "contentRange": null,
      "contentSettings": {
        "cacheControl": null,
        "contentDisposition": null,
        "contentEncoding": null,
        "contentLanguage": null,
        "contentMd5": null,
        "contentType": "application/octet-stream"
      },
      "copy": {
        "completionTime": null,
        "id": null,
        "progress": null,
        "source": null,
        "status": null,
        "statusDescription": null
      },
      "creationTime": "2019-11-12T15:05:43+00:00",
      "deletedTime": null,
      "etag": "0x8D7678258D549A7",
      "lastModified": "2019-11-12T15:09:42+00:00",
      "lease": {
        "duration": null,
        "state": "available",
        "status": "unlocked"
      },
      "pageBlobSequenceNumber": null,
      "remainingRetentionDays": null,
      "serverEncrypted": true
    },
    "snapshot": null
  },
  {
    "content": null,
    "deleted": false,
    "metadata": null,
    "name": "topics/blob_topic/partition=0/blob_topic+0+0000000006.avro",
    "properties": {
      "appendBlobCommittedBlockCount": null,
      "blobTier": "Hot",
      "blobTierChangeTime": null,
      "blobTierInferred": true,
      "blobType": "BlockBlob",
      "contentLength": 213,
      "contentRange": null,
      "contentSettings": {
        "cacheControl": null,
        "contentDisposition": null,
        "contentEncoding": null,
        "contentLanguage": null,
        "contentMd5": null,
        "contentType": "application/octet-stream"
      },
      "copy": {
        "completionTime": null,
        "id": null,
        "progress": null,
        "source": null,
        "status": null,
        "statusDescription": null
      },
      "creationTime": "2019-11-12T15:05:43+00:00",
      "deletedTime": null,
      "etag": "0x8D7678258FFE3CE",
      "lastModified": "2019-11-12T15:09:43+00:00",
      "lease": {
        "duration": null,
        "state": "available",
        "status": "unlocked"
      },
      "pageBlobSequenceNumber": null,
      "remainingRetentionDays": null,
      "serverEncrypted": true
    },
    "snapshot": null
  }
]
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
