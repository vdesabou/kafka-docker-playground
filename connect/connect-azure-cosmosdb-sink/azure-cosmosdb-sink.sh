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
AZURE_NAME=pg${USER}cs${GITHUB_RUN_NUMBER}${TAG}
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
TOPIC_MAP="hotels#${AZURE_COSMOSDB_DB_NAME}"

# generate data file for externalizing secrets
sed -e "s|:AZURE_COSMOSDB_DB_ENDPOINT_URI:|$AZURE_COSMOSDB_DB_ENDPOINT_URI|g" \
    -e "s|:AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY:|$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY|g" \
    -e "s|:AZURE_COSMOSDB_DB_NAME:|$AZURE_COSMOSDB_DB_NAME|g" \
    -e "s|:TOPIC_MAP:|$TOPIC_MAP|g" \
    ../../connect/connect-azure-cosmosdb-sink/data.template > ../../connect/connect-azure-cosmosdb-sink/data

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Write data to topic hotels"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic hotels << EOF
{"id": "h1", "HotelName": "Marriott", "Description": "Marriott description"}
{"id": "h2", "HotelName": "HolidayInn", "Description": "HolidayInn description"}
{"id": "h3", "HotelName": "Motel8", "Description": "Motel8 description"}
EOF

# https://github.com/microsoft/kafka-connect-cosmosdb/blob/dev/doc/README_Sink.md
log "Creating Azure Cosmos DB Sink connector"
playground connector create-or-update --connector azure-cosmosdb-sink << EOF
{
                "connector.class": "com.azure.cosmos.kafka.connect.sink.CosmosDBSinkConnector",
                "tasks.max": "1",
                "topics": "hotels",
                "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "key.converter.schemas.enable": "false",
                "connect.cosmos.connection.endpoint": "\${file:/data:AZURE_COSMOSDB_DB_ENDPOINT_URI}",
                "connect.cosmos.master.key": "\${file:/data:AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY}",
                "connect.cosmos.databasename": "\${file:/data:AZURE_COSMOSDB_DB_NAME}",
                "connect.cosmos.containers.topicmap": "\${file:/data:TOPIC_MAP}"
          }
EOF

sleep 10

log "Verify data from Azure Cosmos DB"
docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI=$AZURE_COSMOSDB_DB_ENDPOINT_URI -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY=$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY -e AZURE_COSMOSDB_DB_NAME=$AZURE_COSMOSDB_DB_NAME -e AZURE_COSMOSDB_CONTAINER_NAME=$AZURE_COSMOSDB_CONTAINER_NAME azure-cosmos-client bash -c "python /get-data.py" > /tmp/result.log  2>&1

cat /tmp/result.log
grep "Marriott" /tmp/result.log
grep "HolidayInn" /tmp/result.log
grep "Motel8" /tmp/result.log

log "Delete Cosmos DB instance"
az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
