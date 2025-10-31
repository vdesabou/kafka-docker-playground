#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend
for component in simple-send
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11-alpine mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

AZURE_NAME=pg${USER}fmfeh${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_EVENT_HUBS_NAMESPACE=ns$AZURE_NAME
AZURE_EVENT_HUBS_NAME=hub$AZURE_NAME
AZURE_REGION=westeurope

bootstrap_ccloud_environment "azure" "$AZURE_REGION"

login_and_maybe_set_azure_subscription

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

log "Creating Azure Event Hubs namespace"
az eventhubs namespace create \
    --name $AZURE_EVENT_HUBS_NAMESPACE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --enable-kafka true \
    --tags cflt_managed_by=user cflt_managed_id="$USER"
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

log "Get Connection String for SimpleSend client"
AZURE_EVENT_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryConnectionString')
    
docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

connector_name="AzureEventHubsSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureEventHubsSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",

    "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
    "azure.eventhubs.sas.key": "$AZURE_SAS_KEY",
    "azure.eventhubs.namespace": "$AZURE_EVENT_HUBS_NAMESPACE",
    "azure.eventhubs.hub.name": "$AZURE_EVENT_HUBS_NAME",
    "kafka.topic": "event_hub_topic",
    "max.events": "50",

    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Inject data in Event Hubs, using simple-send java program"
docker exec -d -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_CONNECTION_STRING="$AZURE_EVENT_CONNECTION_STRING" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"

sleep 5

log "Verifying topic event_hub_topic"
playground topic consume --topic event_hub_topic --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name