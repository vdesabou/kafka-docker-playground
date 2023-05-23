#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99"; then
    # skipped
    logwarn "WARN: skipped as does not work with JDK 8, see https://github.com/microsoft/kafka-connect-cosmosdb/issues/413"
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
TOPIC_MAP="apparels#${AZURE_COSMOSDB_DB_NAME}"

# generate data file for externalizing secrets
sed -e "s|:AZURE_COSMOSDB_DB_ENDPOINT_URI:|$AZURE_COSMOSDB_DB_ENDPOINT_URI|g" \
    -e "s|:AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY:|$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY|g" \
    -e "s|:AZURE_COSMOSDB_DB_NAME:|$AZURE_COSMOSDB_DB_NAME|g" \
    -e "s|:TOPIC_MAP:|$TOPIC_MAP|g" \
    ../../connect/connect-azure-cosmosdb-source/data.template > ../../connect/connect-azure-cosmosdb-source/data

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create kafka topic apparels"
docker exec broker kafka-topics --bootstrap-server 127.0.0.1:9092 --create --topic apparels --partitions 1 --replication-factor 1

log "Send messages to Azure Cosmos DB"
docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI="$AZURE_COSMOSDB_DB_ENDPOINT_URI" -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY="$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY" -e AZURE_COSMOSDB_DB_NAME="$AZURE_COSMOSDB_DB_NAME" -e AZURE_COSMOSDB_CONTAINER_NAME="$AZURE_COSMOSDB_CONTAINER_NAME" azure-cosmos-client bash -c "python /insert-data.py"

# https://github.com/microsoft/kafka-connect-cosmosdb/blob/dev/doc/README_Source.md#source-configuration-properties
log "Creating Azure Cosmos DB Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "com.azure.cosmos.kafka.connect.source.CosmosDBSourceConnector",
                "tasks.max": "1",
                "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "key.converter.schemas.enable": "false",
                "connect.cosmos.task.poll.interval": "100",
                "connect.cosmos.connection.endpoint": "${file:/data:AZURE_COSMOSDB_DB_ENDPOINT_URI}",
                "connect.cosmos.master.key": "${file:/data:AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY}",
                "connect.cosmos.databasename": "${file:/data:AZURE_COSMOSDB_DB_NAME}",
                "connect.cosmos.containers.topicmap": "${file:/data:TOPIC_MAP}",
                "connect.cosmos.offset.useLatest": false,
                "errors.tolerance": "all",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/azure-cosmosdb-source/config | jq .

sleep 30

log "Send again messages to Azure Cosmos DB"
docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI="$AZURE_COSMOSDB_DB_ENDPOINT_URI" -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY="$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY" -e AZURE_COSMOSDB_DB_NAME="$AZURE_COSMOSDB_DB_NAME" -e AZURE_COSMOSDB_CONTAINER_NAME="$AZURE_COSMOSDB_CONTAINER_NAME" azure-cosmos-client bash -c "python /insert-data.py"

log "Verifying topic apparels"
playground topic consume --topic apparels --min-expected-messages 9

log "Delete Cosmos DB instance"
az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
