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
AZURE_DATALAKE_ACCOUNT_NAME=$AZURE_NAME
AZURE_AD_APP_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
AZURE_DATALAKE_CLIENT_ID=$(az ad app list --display-name $AZURE_AD_APP_NAME | jq -r '.[].objectId')
az ad app delete --id $AZURE_DATALAKE_CLIENT_ID
set -e

log "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

log "Registering active directory App $AZURE_AD_APP_NAME"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --password mypassword --native-app false --available-to-other-tenants false --query appId -o tsv)

log "Creating Service Principal associated to the App"
SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.objectId')

AZURE_TENANT_ID=$(az account list | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

log "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az dls account create --account $AZURE_DATALAKE_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP

log "Giving permission to app $AZURE_AD_APP_NAME to get access to data lake $AZURE_DATALAKE_ACCOUNT_NAME"
az dls fs access set-entry --account $AZURE_DATALAKE_ACCOUNT_NAME  --acl-spec user:$SERVICE_PRINCIPAL_ID:rwx --path /

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating Data Lake Storage Gen1 Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.datalake.gen1.AzureDataLakeGen1StorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "datalake_topic",
                    "flush.size": "3",
                    "azure.datalake.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.client.key": "mypassword",
                    "azure.datalake.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-datalake-gen1-sink/config | jq .


log "Sending messages to topic datalake_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 20

log "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az dls fs list --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --path /topics

log "Getting one of the avro files locally and displaying content with avro-tools"
az dls fs download --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --overwrite --source-path /topics/datalake_topic/partition=0/datalake_topic+0+0000000000.avro --destination-path /tmp/datalake_topic+0+0000000000.avro

docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/datalake_topic+0+0000000000.avro

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes

log "Deleting active directory app"
az ad app delete --id $AZURE_DATALAKE_CLIENT_ID