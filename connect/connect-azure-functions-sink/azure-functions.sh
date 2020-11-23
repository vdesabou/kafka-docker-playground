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

AZURE_NAME=playground$USER$GITHUB_RUN_ID.$GITHUB_RUN_NUMBER
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_STORAGE_NAME=$AZURE_NAME
AZURE_FUNCTIONS_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
rm -rf $PWD/LocalFunctionProj
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

rm -rf $PWD/LocalFunctionProj
log "Creating local functions project with HTTP trigger"
# https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function-azure-cli?pivots=programming-language-javascript&tabs=bash%2Cbrowser
docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:3.0-node12-core-tools bash -c "func init LocalFunctionProj --javascript && cd LocalFunctionProj && func new --name HttpExample --template \"HTTP trigger\""

log "Creating functions app $AZURE_FUNCTIONS_NAME"
az functionapp create --consumption-plan-location $AZURE_REGION --name $AZURE_FUNCTIONS_NAME --resource-group $AZURE_RESOURCE_GROUP --runtime node --storage-account $AZURE_STORAGE_NAME --runtime-version 10 --functions-version 3

log "Publishing functions app, it will take a while"
max_attempts="10"
sleep_interval="60"
attempt_num=1

until docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:3.0-node12-core-tools bash -c "az login -u \"$AZ_USER\" -p \"$AZ_PASS\" && cd LocalFunctionProj && func azure functionapp publish \"$AZURE_FUNCTIONS_NAME\""
do
    if (( attempt_num == max_attempts ))
    then
        logerror "ERROR: Failed after $attempt_num attempts. Please troubleshoot and run again."
        return 1
    else
        log "Retrying after $sleep_interval seconds"
        ((attempt_num++))
        sleep $sleep_interval
    fi
done


output=$(docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:3.0-node12-core-tools bash -c "az login -u \"$AZ_USER\" -p \"$AZ_PASS\" > /dev/null && cd LocalFunctionProj && func azure functionapp list-functions $AZURE_FUNCTIONS_NAME --show-keys")
FUNCTIONS_URL=$(echo $output | grep -Eo 'https://[^ >]+'|head -1)

log "Functions URL is $FUNCTIONS_URL"

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

log "Confirm that the messages were delivered to the result topic in Kafka"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-result --from-beginning --max-messages 3

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes