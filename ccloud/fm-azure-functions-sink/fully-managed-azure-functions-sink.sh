#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

login_and_maybe_set_azure_subscription

AZURE_NAME=pgfm${USER}fm${GITHUB_RUN_NUMBER}${TAG}
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
az functionapp create --consumption-plan-location $AZURE_REGION --name $AZURE_FUNCTIONS_NAME --resource-group $AZURE_RESOURCE_GROUP --runtime node --storage-account $AZURE_STORAGE_NAME --runtime-version 18 --functions-version 4 --tags owner_email=$AZ_USER --disable-app-insights true

log "Publishing functions app, it will take a while"
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
    output=$(docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:4-node20-core-tools bash -c "az login -u \"$AZ_USER\" -p \"$AZ_PASS\" > /dev/null 2>&1 && cd LocalFunctionProj && func azure functionapp list-functions $AZURE_FUNCTIONS_NAME --show-keys")
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

bootstrap_ccloud_environment

set +e
playground topic delete --topic functions-test
sleep 3
playground topic create --topic functions-test --nb-partitions 1
set -e


connector_name="AzureFunctionsSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureFunctionsSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "functions-test",
    "function.url": "$FUNCTIONS_URL",
    "function.key": "HttpExample",
    "input.data.format" : "BYTES",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Sending messages to topic functions-test"
playground topic produce -t functions-test --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

sleep 10

connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 3 --timeout 60

playground topic consume --topic error-$connectorId --min-expected-messages 0 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name