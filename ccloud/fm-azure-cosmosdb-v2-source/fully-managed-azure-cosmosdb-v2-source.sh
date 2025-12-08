#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

login_and_maybe_set_azure_subscription

# https://github.com/microsoft/kafka-connect-cosmosdb/blob/dev/doc/CosmosDB_Setup.md
AZURE_NAME=pg${USER}fmck${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_REGION=${AZURE_REGION:-westeurope}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_COSMOSDB_SERVER_NAME=$AZURE_NAME
AZURE_COSMOSDB_DB_NAME=$AZURE_NAME
AZURE_COSMOSDB_CONTAINER_NAME=$AZURE_NAME

bootstrap_ccloud_environment "azure" "$AZURE_REGION"

set +e
playground topic delete --topic apparels
sleep 3
playground topic create --topic apparels --nb-partitions 1
set -e


set +e
log "Delete Cosmos DB instance and resource group (it might fail)"
az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER cflt_managed_by=user cflt_managed_id="$USER"

sleep 10

log "Creating Cosmos DB server $AZURE_COSMOSDB_SERVER_NAME"
az cosmosdb create \
    --name $AZURE_COSMOSDB_SERVER_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --locations regionName=$AZURE_REGION \
    --tags cflt_managed_by=user cflt_managed_id="$USER"

function cleanup_cloud_resources {
    set +e
    log "Delete Cosmos DB instance"
    check_if_continue
    az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes

    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
}
trap cleanup_cloud_resources EXIT

log "Create the database"
az cosmosdb sql database create \
    --name $AZURE_COSMOSDB_DB_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --account-name $AZURE_COSMOSDB_SERVER_NAME \
    --throughput 400

log "Create the container"
az cosmosdb sql container create \
    --name $AZURE_COSMOSDB_CONTAINER_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --account-name $AZURE_COSMOSDB_SERVER_NAME \
    --database-name $AZURE_COSMOSDB_DB_NAME \
    --partition-key-path "/id"

# With the Azure Cosmos DB instance setup, you will need to get the Cosmos DB endpoint URI and primary connection key. These values will be used to setup the Cosmos DB Source and Sink connectors.
AZURE_COSMOSDB_DB_ENDPOINT_URI="https://${AZURE_COSMOSDB_DB_NAME}.documents.azure.com:443/"
log "Cosmos DB endpoint URI is $AZURE_COSMOSDB_DB_ENDPOINT_URI"

# get Cosmos DB primary connection key
AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY=$(az cosmosdb keys list -n $AZURE_COSMOSDB_DB_NAME -g $AZURE_RESOURCE_GROUP --query primaryMasterKey -o tsv)

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

connector_name="CosmosDbSourceV2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "CosmosDbSourceV2",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "input.data.format": "JSON",
    "azure.cosmos.account.endpoint": "$AZURE_COSMOSDB_DB_ENDPOINT_URI",
    "azure.cosmos.account.key": "$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY",
    "azure.cosmos.source.database.name": "$AZURE_COSMOSDB_DB_NAME",
    "azure.cosmos.source.containers.includeAll": "true",
    "azure.cosmos.source.containers.includedList":"$AZURE_COSMOSDB_CONTAINER_NAME",
    "azure.cosmos.source.containers.topicMap": "apparels#${AZURE_COSMOSDB_DB_NAME}",

    "output.data.format": "AVRO",
    "topics": "hotels",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Send messages to Azure Cosmos DB"
docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI="$AZURE_COSMOSDB_DB_ENDPOINT_URI" -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY="$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY" -e AZURE_COSMOSDB_DB_NAME="$AZURE_COSMOSDB_DB_NAME" -e AZURE_COSMOSDB_CONTAINER_NAME="$AZURE_COSMOSDB_CONTAINER_NAME" azure-cosmos-client bash -c "python /insert-data.py"

sleep 30

log "Send again messages to Azure Cosmos DB"
docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI="$AZURE_COSMOSDB_DB_ENDPOINT_URI" -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY="$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY" -e AZURE_COSMOSDB_DB_NAME="$AZURE_COSMOSDB_DB_NAME" -e AZURE_COSMOSDB_CONTAINER_NAME="$AZURE_COSMOSDB_CONTAINER_NAME" azure-cosmos-client bash -c "python /insert-data.py"

log "Verifying topic apparels"
playground topic consume --topic apparels --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name