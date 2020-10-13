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
    az login -u "$AZ_USER" -p "$AZ_PASS"
else
    log "Logging to Azure using browser"
    az login
fi

AZURE_NAME=playground$USER$TRAVIS_JOB_NUMBER
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_STORAGE_NAME=$AZURE_NAME
AZURE_FUNCTIONS_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

log "Creating storage account $AZURE_STORAGE_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_STORAGE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS

# functions app was generated following https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-function-linux-custom-image?tabs=bash%2Cportal&pivots=programming-language-javascript

log "Creating functions app $AZURE_FUNCTIONS_NAME"
az functionapp create --consumption-plan-location $AZURE_REGION --name $AZURE_FUNCTIONS_NAME --resource-group $AZURE_RESOURCE_GROUP --runtime node --storage-account $AZURE_STORAGE_NAME --deployment-container-image-name vdesabou/azurefunctionsimage:v1.0.0

storageConnectionString=$(az storage account show-connection-string --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_STORAGE_NAME --query connectionString --output tsv)

az functionapp config appsettings set --name $AZURE_FUNCTIONS_NAME --resource-group $AZURE_RESOURCE_GROUP  --settings AzureWebJobsStorage=$storageConnectionString

subscription_id="4aef46e4-5a41-4867-9f2e-fa4a3b9dd2d2"
URI="/subscriptions/$subscription_id/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$AZURE_FUNCTIONS_NAME/host/default/listKeys?api-version=2018-11-01"

KEY=$(az rest --method post --uri $URI --query functionKeys.default --output tsv)

FUNCTIONS_URL="https://$AZURE_FUNCTIONS_NAME.azurewebsites.net/api/$AZURE_FUNCTIONS_NAME?code=$KEY"
log "Functions URL is $FUNCTIONS_URL"
exit 0

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic functions-test"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic functions-test --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

log "Creating Azure Functions Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.functions.AzureFunctionsSinkConnector",
                "tasks.max": "1",
                "topics": "functions-test",
                "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                "value.converter":"org.apache.kafka.connect.storage.StringConverter",
                "function.url": "'"$FUNCTIONS_URL"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1",
                "reporter.bootstrap.servers": "broker:9092",
                "reporter.error.topic.name": "test-error",
                "reporter.error.topic.replication.factor": 1,
                "reporter.error.topic.key.format": "string",
                "reporter.error.topic.value.format": "string",
                "reporter.result.topic.name": "test-result",
                "reporter.result.topic.key.format": "string",
                "reporter.result.topic.value.format": "string",
                "reporter.result.topic.replication.factor": 1
          }' \
     http://localhost:8083/connectors/azure-functions-sink/config | jq .


sleep 10

log "Searching Azure Search index"
curl -X GET \
"https://${AZURE_SEARCH_SERVICE_NAME}.search.windows.net/indexes/functions-test-index/docs?api-version=2019-05-06&search=*" \
-H 'Content-Type: application/json' \
-H "api-key: $AZURE_SEARCH_ADMIN_PRIMARY_KEY" | jq

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes