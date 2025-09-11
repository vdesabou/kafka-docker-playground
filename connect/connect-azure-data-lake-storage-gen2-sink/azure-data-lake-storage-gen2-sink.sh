#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.5.99"
then
     logwarn "minimal supported connector version is 1.6.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}dl${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
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
    --tags owner_email=$AZ_USER cflt_managed_by=user cflt_managed_id="$USER"

function cleanup_cloud_resources {
    set +e
    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
}
trap cleanup_cloud_resources EXIT

AZURE_RESOURCE_GROUP_ID=$(az group show --name $AZURE_RESOURCE_GROUP | jq -r '.id')

set +e
log "Registering active directory App $AZURE_AD_APP_NAME, it might fail if already exist"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
if [ $? != 0 ]
then
    log "Failed to create Azure AD App. Attempting to delete existing app and recreate."
    EXISTING_APP_ID=$(az ad app list --display-name "$AZURE_AD_APP_NAME" --query "[0].appId" -o tsv)
    if [ ! -z "$EXISTING_APP_ID" ]
    then
        az ad app delete --id "$EXISTING_APP_ID"
        AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
    fi
fi
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

tenantId=$(az account list --query "[?isDefault].tenantId" | jq -r '.[0]')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$tenantId/oauth2/token"

log "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --tags cflt_managed_by=user cflt_managed_id="$USER"

sleep 20

log "Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID"
az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner" --scope $AZURE_RESOURCE_GROUP_ID

# Ensure the role assignment has been applied
sleep 30

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

playground  tools read-avro-file --file /tmp/datalake_topic+0+0000000000.avro

# keep AD app
# log "Deleting active directory app"
# az ad app delete --id $AZURE_DATALAKE_CLIENT_ID

