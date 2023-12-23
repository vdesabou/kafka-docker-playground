#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend
for component in simple-send
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done



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

AZURE_NAME=pg${USER}eh${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_EVENT_HUBS_NAMESPACE=ns$AZURE_NAME
AZURE_EVENT_HUBS_NAME=hub$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER
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

log "Get Connection String for SimpleSend client"
AZURE_EVENT_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryConnectionString')

# generate data file for externalizing secrets
sed -e "s|:AZURE_SAS_KEY:|$AZURE_SAS_KEY|g" \
    -e "s|:AZURE_EVENT_HUBS_NAMESPACE:|$AZURE_EVENT_HUBS_NAMESPACE|g" \
    -e "s|:AZURE_EVENT_HUBS_NAME:|$AZURE_EVENT_HUBS_NAME|g" \
    ../../connect/connect-azure-event-hubs-source/data.template > ../../connect/connect-azure-event-hubs-source/data

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Azure Event Hubs Source connector"
playground connector create-or-update --connector azure-event-hubs-source << EOF
{
    "connector.class": "io.confluent.connect.azure.eventhubs.EventHubsSourceConnector",
    "kafka.topic": "event_hub_topic",
    "tasks.max": "1",
    "max.events": "1",
    "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
    "azure.eventhubs.sas.key": "\${file:/data:AZURE_SAS_KEY}",
    "azure.eventhubs.namespace": "\${file:/data:AZURE_EVENT_HUBS_NAMESPACE}",
    "azure.eventhubs.hub.name": "\${file:/data:AZURE_EVENT_HUBS_NAME}",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 5

log "Inject data in Event Hubs, using simple-send java program"
docker exec -d -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_CONNECTION_STRING="$AZURE_EVENT_CONNECTION_STRING" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"

sleep 5

log "Verifying topic event_hub_topic"
playground topic consume --topic event_hub_topic --min-expected-messages 2 --timeout 60

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait