#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


# https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend
if [ ! -f ${DIR}/simple-send/target/simplesend-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar simplesend-1.0.0-jar-with-dependencies.jar"
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/simple-send":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/simple-send/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    log "Logging to Azure using environment variables AZ_USER and AZ_PASS"
    set +e
    az logout
    set -e
    az login -u "$AZ_USER" -p "$AZ_PASS"
else
    log "Logging to Azure using browser"
    az login
fi

AZURE_NAME=playground$USER$GITHUB_RUN_ID.$GITHUB_RUN_NUMBER
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_EVENT_HUBS_NAMESPACE=$AZURE_NAME
AZURE_EVENT_HUBS_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
log "Creating Azure Event Hubs namespace"
az eventhubs namespace create \
    --name $AZURE_EVENT_HUBS_NAMESPACE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --enable-kafka true
log "Creating Azure Event Hubs"
az eventhubs eventhub create \
    --name $AZURE_EVENT_HUBS_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE
log "Get SAS key for RootManageSharedAccessKey"
AZURE_SAS_KEY=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryKey')

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Azure Event Hubs Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.eventhubs.EventHubsSourceConnector",
                "kafka.topic": "event_hub_topic",
                "tasks.max": "1",
                "max.events": "1",
                "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
                "azure.eventhubs.sas.key": "'"$AZURE_SAS_KEY"'",
                "azure.eventhubs.namespace": "'"$AZURE_EVENT_HUBS_NAMESPACE"'",
                "azure.eventhubs.hub.name": "'"$AZURE_EVENT_HUBS_NAME"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-event-hubs-source/config | jq .

sleep 5

log "Inject data in Event Hubs, using simple-send java program"
docker exec -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_HUBS_NAMESPACE="$AZURE_EVENT_HUBS_NAMESPACE" -e AZURE_SAS_KEYNAME="RootManageSharedAccessKey" -e AZURE_SAS_KEY="$AZURE_SAS_KEY" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"

sleep 5

log "Verifying topic event_hub_topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic event_hub_topic --from-beginning --max-messages 10

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes