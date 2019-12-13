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

echo "Logging to Azure using browser"
az login

AZURE_RANDOM=$RANDOM
AZURE_RESOURCE_GROUP=delete$AZURE_RANDOM
AZURE_DATALAKE_ACCOUNT_NAME=delete$AZURE_RANDOM
AZURE_AD_APP_NAME=delete$AZURE_RANDOM
AZURE_REGION=westeurope

echo "Add the CLI extension for Azure Data Lake Gen 2"
az extension add --name storage-preview

echo "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

echo "Registering active directory App $AZURE_AD_APP_NAME"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --password mypassword --native-app false --available-to-other-tenants false --query appId -o tsv)

echo "Creating Service Principal associated to the App"
SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.objectId')

AZURE_TENANT_ID=$(az account list | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

echo "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true

sleep 20

echo "Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID"
az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner"

echo AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID"
echo AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME"
echo AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT"
echo SERVICE_PRINCIPAL_ID="$SERVICE_PRINCIPAL_ID"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating Data Lake Storage Gen2 Sink connector"
docker exec -e AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID" -e AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME" -e AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/azure-datalake-gen2-sink/config | jq .


echo "Sending messages to topic datalake_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 20

echo "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az storage blob list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --container-name topics

rm -f /tmp/datalake_topic+0+0000000000.avro
echo "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download  --container-name topics --name datalake_topic/partition=0/datalake_topic+0+0000000000.avro --file /tmp/datalake_topic+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

# brew install avro-tools
avro-tools tojson /tmp/datalake_topic+0+0000000000.avro