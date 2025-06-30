#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "2.0.6"
then
     logwarn "minimal supported connector version is 2.0.7 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}f${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
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
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER

function cleanup_cloud_resources {
    set +e
    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
}
trap cleanup_cloud_resources EXIT

log "Creating storage account $AZURE_STORAGE_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_STORAGE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    rm -rf $PWD/LocalFunctionProj
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo rm -rf $PWD/LocalFunctionProj
    ls -lrt
fi

log "Creating local functions project with HTTP trigger"
# https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function-azure-cli?pivots=programming-language-javascript&tabs=bash%2Cbrowser
docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:4-node20-core-tools bash -c "func init LocalFunctionProj --javascript && cd LocalFunctionProj && func new --name HttpExample --template \"HTTP trigger\" --authlevel \"anonymous\""

log "Creating functions app $AZURE_FUNCTIONS_NAME"
az functionapp create --consumption-plan-location "$AZURE_REGION" --name "$AZURE_FUNCTIONS_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --runtime node --storage-account "$AZURE_STORAGE_NAME" --runtime-version 22 --functions-version 4 --tags owner_email="$AZ_USER" --disable-app-insights true

# Check if the function app was created successfully
if [ $? -eq 0 ]
then
    log "Azure Function App created successfully."
else
    logerror "❌ Failed to create Azure Function App."
    exit 1
fi

sleep 10

log "Publishing functions app $AZURE_FUNCTIONS_NAME, it will take a while"
max_attempts="10"
sleep_interval="60"
attempt_num=1

until docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:4-node20-core-tools bash -c "az login -u \"$AZ_USER\" -p \"$AZ_PASS\" > /dev/null 2>&1 && cd LocalFunctionProj && func azure functionapp publish \"$AZURE_FUNCTIONS_NAME\""
do
    if (( attempt_num == max_attempts ))
    then
        logerror "❌ Failed after $attempt_num attempts. Please troubleshoot and run again."
        exit 1
    else
        log "Retrying after $sleep_interval seconds"
        ((attempt_num++))
        sleep $sleep_interval
    fi
done

max_attempts="10"
sleep_interval="30"
attempt_num=1

until [ ! -z "$FUNCTIONS_URL" ]
do
    output=$(docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:4-node20-core-tools bash -c "az login -u \"$AZ_USER\" -p \"$AZ_PASS\" > /dev/null 2>&1 && cd LocalFunctionProj && func azure functionapp list-functions \"$AZURE_FUNCTIONS_NAME\" --show-keys")

    FUNCTIONS_URL=$(echo "$output" | grep "Invoke url" | grep -Eo 'https://[^ >]+' | head -1)

    if [ ! -z "$FUNCTIONS_URL" ]
    then
        log "Functions URL is $FUNCTIONS_URL"
    else
        if (( attempt_num == max_attempts ))
        then
            logerror "❌ Failed to retrieve FUNCTIONS_URL after $attempt_num attempts. Please troubleshoot and run again."
            exit 1
        else
            log "Retrying to get FUNCTIONS_URL after $sleep_interval seconds"
            ((attempt_num++))
            sleep $sleep_interval
        fi
    fi
done

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic functions-test"
playground topic produce -t functions-test --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

log "Creating Azure Functions Sink connector"
playground connector create-or-update --connector azure-functions-sink  << EOF
{
    "connector.class": "io.confluent.connect.azure.functions.AzureFunctionsSinkConnector",
    "tasks.max": "1",
    "topics": "functions-test",
    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
    "value.converter":"org.apache.kafka.connect.storage.StringConverter",
    "function.url": "$FUNCTIONS_URL",
    "function.key": "",
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
}
EOF


sleep 10

log "Confirm that the messages were delivered to the result topic in Kafka"
playground topic consume --topic test-result --min-expected-messages 3 --timeout 60