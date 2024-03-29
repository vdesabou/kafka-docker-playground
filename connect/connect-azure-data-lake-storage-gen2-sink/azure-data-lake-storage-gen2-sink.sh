#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

AZURE_SUBSCRIPTION_NAME=${AZURE_SUBSCRIPTION_NAME:-$1}

if [ -z "$AZURE_SUBSCRIPTION_NAME" ]
then
     logerror "AZURE_SUBSCRIPTION_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# when AZURE_SUBSCRIPTION_NAME env var is set, we need to set the correct subscription
maybe_set_azure_subscription

AZURE_NAME=pg${USER}dl${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_DATALAKE_ACCOUNT_NAME=$AZURE_NAME
AZURE_AD_APP_NAME=pg${USER}
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
# keep AD app
# AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
# az ad app delete --id $AZURE_DATALAKE_CLIENT_ID
set -e

log "Add the CLI extension for Azure Data Lake Gen 2"
az extension add --name storage-preview

log "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER

AZURE_RESOURCE_GROUP_ID=$(az group show --name $AZURE_RESOURCE_GROUP | jq -r '.id')

set +e
log "Registering active directory App $AZURE_AD_APP_NAME, it might fail if already exist"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
AZURE_DATALAKE_CLIENT_PASSWORD=$(az ad app credential reset --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.password')
set -e

if [ "$AZURE_DATALAKE_CLIENT_PASSWORD" == "" ]
then
  logerror "password could not be retrieved"
  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    az ad app credential reset --id $AZURE_DATALAKE_CLIENT_ID
  fi
  exit 1
fi

log "Getting Service Principal associated to the App $AZURE_DATALAKE_CLIENT_ID"
set +e
SERVICE_PRINCIPAL_ID=$(az ad sp show --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.id')
if [ $? != 0 ] || [ "$SERVICE_PRINCIPAL_ID" == "" ]
then
  log "Service Principal does not appear to exist...Creating Service Principal associated to the App $AZURE_DATALAKE_CLIENT_ID" 
  SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.id')
  if [ $? != 0 ]
  then
    logerror "❌ Could not get or create Service Principal associated to the App $AZURE_DATALAKE_CLIENT_ID"
    exit 1
  fi
fi
set -e

AZURE_TENANT_ID=$(az account list --query "[?name=='$AZURE_SUBSCRIPTION_NAME']" | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

log "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2

sleep 20

log "Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID"
az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner" --scope $AZURE_RESOURCE_GROUP_ID

# generate data file for externalizing secrets
sed -e "s|:AZURE_DATALAKE_CLIENT_ID:|$AZURE_DATALAKE_CLIENT_ID|g" \
    -e "s|:AZURE_DATALAKE_CLIENT_PASSWORD:|$AZURE_DATALAKE_CLIENT_PASSWORD|g" \
    -e "s|:AZURE_DATALAKE_ACCOUNT_NAME:|$AZURE_DATALAKE_ACCOUNT_NAME|g" \
    -e "s|:AZURE_DATALAKE_TOKEN_ENDPOINT:|$AZURE_DATALAKE_TOKEN_ENDPOINT|g" \
    ../../connect/connect-azure-data-lake-storage-gen2-sink/data.template > ../../connect/connect-azure-data-lake-storage-gen2-sink/data

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Data Lake Storage Gen2 Sink connector"
playground connector create-or-update --connector azure-datalake-gen2-sink  << EOF
{
    "connector.class": "io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector",
    "tasks.max": "1",
    "topics": "datalake_topic",
    "flush.size": "3",
    "azure.datalake.gen2.client.id": "\${file:/data:AZURE_DATALAKE_CLIENT_ID}",
    "azure.datalake.gen2.client.key": "\${file:/data:AZURE_DATALAKE_CLIENT_PASSWORD}",
    "azure.datalake.gen2.account.name": "\${file:/data:AZURE_DATALAKE_ACCOUNT_NAME}",
    "azure.datalake.gen2.token.endpoint": "\${file:/data:AZURE_DATALAKE_TOKEN_ENDPOINT}",
    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF


playground topic produce -t datalake_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

sleep 20

log "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az storage fs file list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --file-system topics

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download  --container-name topics --name datalake_topic/partition=0/datalake_topic+0+0000000000.avro --file /tmp/datalake_topic+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/datalake_topic+0+0000000000.avro

log "Deleting resource group"
check_if_continue
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait

# keep AD app
# log "Deleting active directory app"
# az ad app delete --id $AZURE_DATALAKE_CLIENT_ID

