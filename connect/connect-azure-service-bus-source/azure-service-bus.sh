#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


# https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-cli#send-and-receive-messages
if [ ! -f ${DIR}/QueuesGettingStarted/target/queuesgettingstarted-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar queuesgettingstarted-1.0.0-jar-with-dependencies.jar"
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/QueuesGettingStarted":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/QueuesGettingStarted/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
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


AZURE_RESOURCE_GROUP=playground$USER$TRAVIS_BUILD_NUMBER
AZURE_SERVICE_BUS_NAMESPACE=playground$USER$TRAVIS_BUILD_NUMBER
AZURE_SERVICE_BUS_QUEUE_NAME=playground$USER$TRAVIS_BUILD_NUMBER
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Azure Service Bus Source connector"
docker exec -e AZURE_SERVICE_BUS_QUEUE_NAME="$AZURE_SERVICE_BUS_QUEUE_NAME" -e AZURE_SERVICE_BUS_NAMESPACE="$AZURE_SERVICE_BUS_NAMESPACE" -e AZURE_SAS_KEY="$AZURE_SAS_KEY" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.servicebus.ServiceBusSourceConnector",
                "kafka.topic": "servicebus-topic",
                "tasks.max": "1",
                "azure.servicebus.sas.keyname": "RootManageSharedAccessKey",
                "azure.servicebus.sas.key": "'"$AZURE_SAS_KEY"'",
                "azure.servicebus.namespace": "'"$AZURE_SERVICE_BUS_NAMESPACE"'",
                "azure.servicebus.entity.name": "'"$AZURE_SERVICE_BUS_QUEUE_NAME"'",
                "azure.servicebus.subscription" : "",
                "azure.servicebus.max.message.count" : "10",
                "azure.servicebus.max.waiting.time.seconds" : "30",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-service-bus-source/config | jq .

sleep 5

log "Inject data in Service Bus, using QueuesGettingStarted java program"
SB_SAMPLES_CONNECTIONSTRING="Endpoint=sb://$AZURE_SERVICE_BUS_NAMESPACE.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=$AZURE_SAS_KEY"
docker exec -e SB_SAMPLES_CONNECTIONSTRING="$SB_SAMPLES_CONNECTIONSTRING" -e AZURE_SERVICE_BUS_QUEUE_NAME="$AZURE_SERVICE_BUS_QUEUE_NAME" simple-send bash -c "java -jar queuesgettingstarted-1.0.0-jar-with-dependencies.jar"

sleep 5

log "Verifying topic servicebus-topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic servicebus-topic --from-beginning --max-messages 10

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes