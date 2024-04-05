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

tenantId=$(az account list --query "[?isDefault].tenantId" | jq -r '.[0]')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$tenantId/oauth2/token"

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


bootstrap_ccloud_environment

set +e
playground topic delete --topic datalake_topic
sleep 3
playground topic create --topic datalake_topic --nb-partitions 1
set -e


connector_name="AzureDataLakeGen2Sink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "AzureDataLakeGen2Sink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "datalake_topic",
  "azure.datalake.gen2.client.id": "$AZURE_DATALAKE_CLIENT_ID",
  "azure.datalake.gen2.client.key": "$AZURE_DATALAKE_CLIENT_PASSWORD",
  "azure.datalake.gen2.account.name": "$AZURE_DATALAKE_ACCOUNT_NAME",
  "azure.datalake.gen2.token.endpoint": "$AZURE_DATALAKE_TOKEN_ENDPOINT",
  "input.data.format" : "AVRO",
  "output.data.format" : "AVRO",
  "time.interval" : "HOURLY",
  "flush.size": "1000",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

playground topic produce -t datalake_topic --nb-messages 1000 --forced-value '{"f1":"value%g"}' << 'EOF'
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

playground connnector show-lag --connector $connector_name

# log "Getting one of the avro files locally and displaying content with avro-tools"
# az storage blob download  --container-name topics --name datalake_topic/partition=0/datalake_topic+0+0000000000.avro --file /tmp/datalake_topic+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

# docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/datalake_topic+0+0000000000.avro

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

log "Deleting resource group"
check_if_continue
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
