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

AZURE_NAME=pg${USER}bs${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_ACCOUNT_NAME=$AZURE_NAME
AZURE_CONTAINER_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER
log "Creating Azure Storage Account $AZURE_ACCOUNT_NAME"
az storage account create \
    --name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --encryption-services blob
AZURE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --query "[0].value" | sed -e 's/^"//' -e 's/"$//')
log "Creating Azure Storage Container $AZURE_CONTAINER_NAME"
az storage container create \
    --account-name $AZURE_ACCOUNT_NAME \
    --account-key $AZURE_ACCOUNT_KEY \
    --name $AZURE_CONTAINER_NAME

bootstrap_ccloud_environment

set +e
playground topic delete --topic quickstart
sleep 3
playground topic create --topic quickstart --nb-partitions 1
set -e

log "Copy generalized.quickstart.json to container $AZURE_CONTAINER_NAME quickstart/generalized.quickstart.json"
cd ../../ccloud/fully-managed-connect-azure-blob-storage-source
rm -f /tmp/generalized.quickstart.json
cp generalized.quickstart.json /tmp/
cd -
az storage blob upload --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name quickstart/generalized.quickstart.json --file /tmp/generalized.quickstart.json

connector_name="AzureBlobSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureBlobSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics.dir": "quickstart",
    "topic.regex.list": "quick-start-topic:.*",
    "azblob.account.name": "$AZURE_ACCOUNT_NAME",
    "azblob.account.key": "$AZURE_ACCOUNT_KEY",
    "azblob.container.name": "$AZURE_CONTAINER_NAME",
    "input.data.format": "JSON",
    "output.data.format" : "JSON",

    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 5

log "Verifying topic quick-start-topic"
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60

log "Deleting resource group"
check_if_continue
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
