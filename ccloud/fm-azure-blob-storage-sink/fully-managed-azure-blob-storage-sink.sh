#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}fmbk${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_ACCOUNT_NAME=$AZURE_NAME
AZURE_CONTAINER_NAME=$AZURE_NAME
AZURE_REGION=${AZURE_REGION:-westeurope}

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
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
log "Creating Azure Storage Account $AZURE_ACCOUNT_NAME"
az storage account create \
    --name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --encryption-services blob \
    --tags cflt_managed_by=user cflt_managed_id="$USER"
AZURE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --query "[0].value" | sed -e 's/^"//' -e 's/"$//')
log "Creating Azure Storage Container $AZURE_CONTAINER_NAME"
az storage container create \
    --account-name $AZURE_ACCOUNT_NAME \
    --account-key $AZURE_ACCOUNT_KEY \
    --name $AZURE_CONTAINER_NAME


bootstrap_ccloud_environment "azure" "$AZURE_REGION"

set +e
playground topic delete --topic blob_topic
sleep 3
playground topic create --topic blob_topic --nb-partitions 1
set -e

connector_name="AzureBlobSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureBlobSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "blob_topic",
    "azblob.account.name": "$AZURE_ACCOUNT_NAME",
    "azblob.account.key": "$AZURE_ACCOUNT_KEY",
    "azblob.container.name": "$AZURE_CONTAINER_NAME",
    "input.data.format" : "AVRO",
    "output.data.format" : "AVRO",
    "time.interval" : "HOURLY",
    "flush.size": "1000",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Sending messages to topic blob_topic"
playground topic produce -t blob_topic --nb-messages 1000 << 'EOF'
{
    "type": "record",
    "namespace": "com.github.vdesabou",
    "name": "Customer",
    "version": "1",
    "fields": [
        {
            "name": "count",
            "type": "long",
            "doc": "count"
        },
        {
            "name": "first_name",
            "type": "string",
            "doc": "First Name of Customer"
        },
        {
            "name": "last_name",
            "type": "string",
            "doc": "Last Name of Customer"
        },
        {
            "name": "address",
            "type": "string",
            "doc": "Address of Customer"
        }
    ]
}
EOF

sleep 10

playground connector show-lag --connector $connector_name

# log "Listing objects of container ${AZURE_CONTAINER_NAME} in Azure Blob Storage"
# az storage fs file list --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" -f "${AZURE_CONTAINER_NAME}" --output table

# log "Getting one of the avro files locally and displaying content with avro-tools"
# az storage blob download --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name topics/blob_topic/year=2024/month=04/day=04/hour=08/blob_topic+0+0000000000.avro --file /tmp/blob_topic+0+0000000000.avro

# playground  tools read-avro-file --file /tmp/blob_topic+0+0000000000.avro


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name