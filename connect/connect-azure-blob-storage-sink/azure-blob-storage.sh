#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "az"

if [ -z "$1" ]
then
    echo "ERROR: AZURE_STORAGE_ACCOUNT has not been provided. Usage: azure-blob-storage.sh <AZURE_STORAGE_ACCOUNT> <AZURE_STORAGE_KEY> [<CONTAINER_NAME>]"
    exit 1
fi

if [ -z "$2" ]
then
    echo "ERROR: AZURE_STORAGE_ACCOUNT has not been provided. Usage: azure-blob-storage.sh <AZURE_STORAGE_ACCOUNT> <AZURE_STORAGE_KEY> [<CONTAINER_NAME>]"
    exit 1
fi

AZURE_STORAGE_ACCOUNT="${1}"
AZURE_STORAGE_KEY="${2}"
CONTAINER_NAME=${3:-blobsink}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Creating Azure Blob Storage Sink connector"
docker exec -e AZURE_STORAGE_ACCOUNT="$AZURE_STORAGE_ACCOUNT" -e AZURE_STORAGE_KEY="$AZURE_STORAGE_KEY" -e CONTAINER_NAME="$CONTAINER_NAME" connect \
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


echo "Sending messages to topic blob_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic blob_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

echo "Listing objects of container ${CONTAINER_NAME} in Azure Blob Storage"
az storage blob list --account-name "${AZURE_STORAGE_ACCOUNT}" --account-key "${AZURE_STORAGE_KEY}" --container-name "${CONTAINER_NAME}" --output table

echo "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download --account-name "${AZURE_STORAGE_ACCOUNT}" --account-key "${AZURE_STORAGE_KEY}" --container-name "${CONTAINER_NAME}" --name topics/blob_topic/partition=0/blob_topic+0+0000000000.avro --file /tmp/blob_topic+0+0000000000.avro

# brew install avro-tools
avro-tools tojson /tmp/blob_topic+0+0000000000.avro