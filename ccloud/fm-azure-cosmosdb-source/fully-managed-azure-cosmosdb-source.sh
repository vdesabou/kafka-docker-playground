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


bootstrap_ccloud_environment

set +e
playground topic delete --topic apparels
sleep 3
playground topic create --topic apparels --nb-partitions 1
set -e

# https://github.com/microsoft/kafka-connect-cosmosdb/blob/dev/doc/CosmosDB_Setup.md
AZURE_NAME=pg${USER}ck${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_REGION=westeurope
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_COSMOSDB_SERVER_NAME=$AZURE_NAME
AZURE_COSMOSDB_DB_NAME=$AZURE_NAME
AZURE_COSMOSDB_CONTAINER_NAME=$AZURE_NAME

set +e
log "Delete Cosmos DB instance and resource group (it might fail)"
az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER

sleep 10

log "Creating Cosmos DB server $AZURE_COSMOSDB_SERVER_NAME"
az cosmosdb create \
    --name $AZURE_COSMOSDB_SERVER_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --locations regionName=$AZURE_REGION

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

connector_name="CosmosDbSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "CosmosDbSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "input.data.format": "JSON",
    "connect.cosmos.connection.endpoint": "$AZURE_COSMOSDB_DB_ENDPOINT_URI",
    "connect.cosmos.master.key": "$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY",
    "connect.cosmos.databasename": "$AZURE_COSMOSDB_DB_NAME",
    "connect.cosmos.containers.topicmap": "apparels#${AZURE_COSMOSDB_DB_NAME}",

    "output.data.format": "JSON",
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

log "Delete Cosmos DB instance"
check_if_continue
az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
