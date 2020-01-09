#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "az"

az login

AZURE_RANDOM=$RANDOM
AZURE_RESOURCE_GROUP=delete$AZURE_RANDOM
AZURE_DATALAKE_ACCOUNT_NAME=delete$AZURE_RANDOM
AZURE_AD_APP_NAME=delete$AZURE_RANDOM
AZURE_REGION=westeurope

echo -e "\033[0;33mCreating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION\033[0m"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

echo -e "\033[0;33mRegistering active directory App $AZURE_AD_APP_NAME\033[0m"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --password mypassword --native-app false --available-to-other-tenants false --query appId -o tsv)

echo -e "\033[0;33mCreating Service Principal associated to the App\033[0m"
SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.objectId')

AZURE_TENANT_ID=$(az account list | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

echo -e "\033[0;33mCreating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP\033[0m"
az dls account create --account $AZURE_DATALAKE_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP

echo -e "\033[0;33mGiving permission to app $AZURE_AD_APP_NAME to get access to data lake $AZURE_DATALAKE_ACCOUNT_NAME\033[0m"
az dls fs access set-entry --account $AZURE_DATALAKE_ACCOUNT_NAME  --acl-spec user:$SERVICE_PRINCIPAL_ID:rwx --path /

echo AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID"
echo AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME"
echo AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT"
echo SERVICE_PRINCIPAL_ID="$SERVICE_PRINCIPAL_ID"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mCreating Data Lake Storage Gen1 Sink connector\033[0m"
docker exec -e AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID" -e AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME" -e AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT" connect \
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


echo -e "\033[0;33mSending messages to topic datalake_topic\033[0m"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 20

echo -e "\033[0;33mListing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake\033[0m"
az dls fs list --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --path /topics

rm -f /tmp/datalake_topic+0+0000000000.avro
echo -e "\033[0;33mGetting one of the avro files locally and displaying content with avro-tools\033[0m"
az dls fs download --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --source-path /topics/datalake_topic/partition=0/datalake_topic+0+0000000000.avro --destination-path /tmp/datalake_topic+0+0000000000.avro


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/datalake_topic+0+0000000000.avro