#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

bootstrap_ccloud_environment




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

AZURE_NAME=pg${USER}sb${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
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

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull


connector_name="AzureServiceBusSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureServiceBusSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",

    "azure.servicebus.sas.keyname": "RootManageSharedAccessKey",
    "azure.servicebus.sas.key": "$AZURE_SAS_KEY",
    "azure.servicebus.namespace": "$AZURE_SERVICE_BUS_NAMESPACE",
    "azure.servicebus.entity.name": "$AZURE_SERVICE_BUS_QUEUE_NAME",
    "azure.servicebus.subscription" : "",
    "azure.servicebus.max.message.count" : "10",
    "azure.servicebus.max.waiting.time.seconds" : "30",
    "kafka.topic": "servicebus-topic",
    "output.data.format": "AVRO",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Inject data in Service Bus, using QueuesGettingStarted java program"
SB_SAMPLES_CONNECTIONSTRING="Endpoint=sb://$AZURE_SERVICE_BUS_NAMESPACE.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=$AZURE_SAS_KEY"
docker exec -e SB_SAMPLES_CONNECTIONSTRING="$SB_SAMPLES_CONNECTIONSTRING" -e AZURE_SERVICE_BUS_QUEUE_NAME="$AZURE_SERVICE_BUS_QUEUE_NAME" simple-send bash -c "java -jar queuesgettingstarted-1.0.0-jar-with-dependencies.jar"

sleep 180

log "Verifying topic servicebus-topic"
playground topic consume --topic servicebus-topic --min-expected-messages 5 --timeout 60

# {"deliveryCount":{"long":1},"enqueuedTimeUtc":{"long":1672745480672},"contentType":null,"label":null,"correlationId":null,"messageProperties":{"string":"{}"},"partitionKey":null,"replyTo":null,"replyToSessionId":null,"deadLetterSource":null,"timeToLive":{"long":-1},"lockedUntilUtc":{"long":1672745540687},"sequenceNumber":{"long":1},"sessionId":null,"lockToken":{"string":"33067f1f-955e-4739-bcef-6e817f09c18d"},"messageBody":{"bytes":"tets"},"getTo":null}
# {"deliveryCount":{"long":1},"enqueuedTimeUtc":{"long":1672745518954},"contentType":{"string":"application/json"},"label":null,"correlationId":null,"messageProperties":{"string":"{}"},"partitionKey":null,"replyTo":null,"replyToSessionId":null,"deadLetterSource":null,"timeToLive":{"long":-1},"lockedUntilUtc":{"long":1672745578985},"sequenceNumber":{"long":2},"sessionId":null,"lockToken":{"string":"27e486c4-d167-4720-abfb-d47bd2553776"},"messageBody":{"bytes":"{\"schema\":{\"type\":\"struct\",\"fields\":[{\"type\":\"int32\",\"optional\":false,\"field\":\"id\"},{\"type\":\"string\",\"optional\":false,\"field\":\"first_name\"},{\"type\":\"string\",\"optional\":false,\"field\":\"last_name\"},{\"type\":\"string\",\"optional\":false,\"field\":\"email\"}],\"optional\":false,\"name\":\"server1.dbo.customers.Value\"},\"payload\":{\"id\":1001,\"first_name\":\"Sally\",\"last_name\":\"Thomas\",\"email\":\"sally.thomas@acme.com\"}}"},"getTo":null}