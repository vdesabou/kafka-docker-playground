#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "az"

log "Logging to Azure using browser"
az login

AZURE_RANDOM=$RANDOM
AZURE_RESOURCE_GROUP=delete$AZURE_RANDOM
AZURE_ACCOUNT_NAME=delete$AZURE_RANDOM
AZURE_CONTAINER_NAME=delete$AZURE_RANDOM
AZURE_REGION=westeurope

az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
az storage account create \
    --name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --encryption blob
az storage container create \
    --account-name $AZURE_ACCOUNT_NAME \
    --name $AZURE_CONTAINER_NAME
AZURE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --output table \
    | grep key1 | awk '{print $3}')

echo AZURE_ACCOUNT_NAME=$AZURE_ACCOUNT_NAME
echo AZURE_ACCOUNT_KEY=$AZURE_ACCOUNT_KEY
echo AZURE_CONTAINER_NAME=$AZURE_CONTAINER_NAME

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Azure Blob Storage Sink connector"
docker exec -e AZURE_ACCOUNT_NAME="$AZURE_ACCOUNT_NAME" -e AZURE_ACCOUNT_KEY="$AZURE_ACCOUNT_KEY" -e AZURE_CONTAINER_NAME="$AZURE_CONTAINER_NAME" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "blob_topic",
                    "flush.size": "3",
                    "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                    "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                    "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                    "format.class": "io.confluent.connect.azure.blob.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-blob-sink/config | jq .


log "Sending messages to topic blob_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic blob_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing objects of container ${AZURE_CONTAINER_NAME} in Azure Blob Storage"
az storage blob list --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --output table

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name topics/blob_topic/partition=0/blob_topic+0+0000000000.avro --file /tmp/blob_topic+0+0000000000.avro


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/blob_topic+0+0000000000.avro