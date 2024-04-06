#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
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

# generate data file for externalizing secrets
sed -e "s|:AZURE_ACCOUNT_NAME:|$AZURE_ACCOUNT_NAME|g" \
    -e "s|:AZURE_ACCOUNT_KEY:|$AZURE_ACCOUNT_KEY|g" \
    -e "s|:AZURE_CONTAINER_NAME:|$AZURE_CONTAINER_NAME|g" \
    ../../connect/connect-azure-blob-storage-source/data.template > ../../connect/connect-azure-blob-storage-source/data

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.backup-and-restore.yml"

DOMAIN="$AZURE_CONTAINER_NAME.blob.core.windows.net"
IP=$(nslookup $DOMAIN | grep Address | grep -v "#" | cut -d " " -f 2 | tail -1)
log "Blocking $DOMAIN IP $IP to make sure proxy is used"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

log "Creating Azure Blob Storage Sink connector"
playground connector create-or-update --connector azure-blob-sink  << EOF
{
    "connector.class": "io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector",
    "tasks.max": "1",
    "topics": "blob_topic",
    "flush.size": "3",
    "azblob.account.name": "\${file:/data:AZURE_ACCOUNT_NAME}",
    "azblob.account.key": "\${file:/data:AZURE_ACCOUNT_KEY}",
    "azblob.container.name": "\${file:/data:AZURE_CONTAINER_NAME}",
    "azblob.proxy.url" : "https://nginx-proxy:8888",
    "format.class": "io.confluent.connect.azure.blob.format.avro.AvroFormat",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF


log "Sending messages to topic blob_topic"
playground topic produce -t blob_topic --nb-messages 10 << 'EOF'
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

log "Listing objects of container ${AZURE_CONTAINER_NAME} in Azure Blob Storage"
az storage fs file list --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" -f "${AZURE_CONTAINER_NAME}" --output table

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name topics/blob_topic/partition=0/blob_topic+0+0000000000.avro --file /tmp/blob_topic+0+0000000000.avro

docker run --quiet --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/blob_topic+0+0000000000.avro


log "Creating Azure Blob Storage Source connector"
playground connector create-or-update --connector azure-blob-source  << EOF
{
    "connector.class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
    "tasks.max": "1",
    "azblob.account.name": "\${file:/data:AZURE_ACCOUNT_NAME}",
    "azblob.account.key": "\${file:/data:AZURE_ACCOUNT_KEY}",
    "azblob.container.name": "\${file:/data:AZURE_CONTAINER_NAME}",
    "azblob.proxy.url" : "https://nginx-proxy:8888",
    "format.class": "io.confluent.connect.cloud.storage.source.format.CloudStorageAvroFormat",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "transforms" : "AddPrefix",
    "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.AddPrefix.regex" : ".*",
    "transforms.AddPrefix.replacement" : "copy_of_\$0"
}
EOF

sleep 5

log "Verifying topic copy_of_blob_topic"
playground topic consume --topic copy_of_blob_topic --min-expected-messages 3 --timeout 60

log "Deleting resource group"
check_if_continue
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
