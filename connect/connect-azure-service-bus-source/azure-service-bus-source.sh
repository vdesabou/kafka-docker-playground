#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-azure-service-bus-source
# https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-cli#send-and-receive-messages
for component in QueuesGettingStarted
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done
cd -

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}sb${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SERVICE_BUS_NAMESPACE=$AZURE_NAME
AZURE_SERVICE_BUS_QUEUE_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER
function cleanup_cloud_resources {
    set +e
    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
}
trap cleanup_cloud_resources EXIT
log "Creating Azure Service Bus namespace"
az servicebus namespace create \
    --name $AZURE_SERVICE_BUS_NAMESPACE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
log "Creating Azure Service Bus Queue"
az servicebus queue create \
    --name $AZURE_SERVICE_BUS_QUEUE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_SERVICE_BUS_NAMESPACE
log "Get SAS key for RootManageSharedAccessKey"
AZURE_SAS_KEY=$(az servicebus namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_SERVICE_BUS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryKey')

# generate data file for externalizing secrets
sed -e "s|:AZURE_SAS_KEY:|$AZURE_SAS_KEY|g" \
    -e "s|:AZURE_SERVICE_BUS_NAMESPACE:|$AZURE_SERVICE_BUS_NAMESPACE|g" \
    -e "s|:AZURE_SERVICE_BUS_QUEUE_NAME:|$AZURE_SERVICE_BUS_QUEUE_NAME|g" \
    ../../connect/connect-azure-service-bus-source/data.template > ../../connect/connect-azure-service-bus-source/data

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Azure Service Bus Source connector"
playground connector create-or-update --connector azure-service-bus-source  << EOF
{
    "connector.class": "io.confluent.connect.azure.servicebus.ServiceBusSourceConnector",
    "kafka.topic": "servicebus-topic",
    "tasks.max": "1",
    "azure.servicebus.sas.keyname": "RootManageSharedAccessKey",
    "azure.servicebus.sas.key": "\${file:/data:AZURE_SAS_KEY}",
    "azure.servicebus.namespace": "\${file:/data:AZURE_SERVICE_BUS_NAMESPACE}",
    "azure.servicebus.entity.name": "\${file:/data:AZURE_SERVICE_BUS_QUEUE_NAME}",
    "azure.servicebus.subscription" : "",
    "azure.servicebus.max.message.count" : "10",
    "azure.servicebus.max.waiting.time.seconds" : "30",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 5

log "Inject data in Service Bus, using QueuesGettingStarted java program"
SB_SAMPLES_CONNECTIONSTRING="Endpoint=sb://$AZURE_SERVICE_BUS_NAMESPACE.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=$AZURE_SAS_KEY"
docker exec -e SB_SAMPLES_CONNECTIONSTRING="$SB_SAMPLES_CONNECTIONSTRING" -e AZURE_SERVICE_BUS_QUEUE_NAME="$AZURE_SERVICE_BUS_QUEUE_NAME" simple-send bash -c "java -jar queuesgettingstarted-1.0.0-jar-with-dependencies.jar"

sleep 180

log "Verifying topic servicebus-topic"
playground topic consume --topic servicebus-topic --min-expected-messages 5 --timeout 60