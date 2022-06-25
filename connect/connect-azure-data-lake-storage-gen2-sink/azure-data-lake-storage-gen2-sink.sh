#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    log "Logging to Azure using environment variables AZ_USER and AZ_PASS"
    set +e
    az logout
    set -e
    az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
else
    log "Logging to Azure using browser"
    az login
fi

AZURE_TENANT_NAME=${AZURE_TENANT_NAME:-$1}

if [ -z "$AZURE_TENANT_NAME" ]
then
     logerror "AZURE_TENANT_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

AZURE_NAME=pg${USER}dl${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_DATALAKE_ACCOUNT_NAME=$AZURE_NAME
AZURE_AD_APP_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
az ad app delete --id $AZURE_DATALAKE_CLIENT_ID
set -e

log "Add the CLI extension for Azure Data Lake Gen 2"
az extension add --name storage-preview

log "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

log "Registering active directory App $AZURE_AD_APP_NAME"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
AZURE_DATALAKE_CLIENT_PASSWORD=$(az ad app credential reset --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.password')

log "Creating Service Principal associated to the App"
SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.id')

AZURE_TENANT_ID=$(az account list --query "[?name=='$AZURE_TENANT_NAME']" | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

log "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hns true

sleep 20

log "Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID"
az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Data Lake Storage Gen2 Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector",
                    "tasks.max": "1",
                    "topics": "datalake_topic",
                    "flush.size": "3",
                    "azure.datalake.gen2.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.gen2.client.key": "'"$AZURE_DATALAKE_CLIENT_PASSWORD"'",
                    "azure.datalake.gen2.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.gen2.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-datalake-gen2-sink/config | jq .


log "Sending messages to topic datalake_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 20

log "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az storage blob list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --container-name topics

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download  --container-name topics --name datalake_topic/partition=0/datalake_topic+0+0000000000.avro --file /tmp/datalake_topic+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/datalake_topic+0+0000000000.avro

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait

log "Deleting active directory app"
az ad app delete --id $AZURE_DATALAKE_CLIENT_ID

