#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f $HOME/secrets.properties ]
     then
          logerror "$HOME/secrets.properties is not present!"
          exit 1
     fi
     source $HOME/secrets.properties
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

AZURE_TENANT_NAME=${AZURE_TENANT_NAME:-$1}

if [ -z "$AZURE_TENANT_NAME" ]
then
     logerror "AZURE_TENANT_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

AZURE_NAME=pg${USER}dl${GITHUB_RUN_NUMBER}${TAG}
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

log "Add the CLI extension for Azure Data Lake Gen 2"
az extension add --name storage-preview

log "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

log "Registering active directory App $AZURE_AD_APP_NAME"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --password mypassword --native-app false --available-to-other-tenants false --query appId -o tsv)

log "Creating Service Principal associated to the App"
SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.objectId')

AZURE_TENANT_ID=$(az account list --query "[?name=='$AZURE_TENANT_NAME']" | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

log "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true

sleep 20

log "Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID"
az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Register schema for customer"
curl -X POST http://localhost:8081/subjects/customer/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"fields\":[{\"name\":\"customer_id\",\"type\":\"int\"},{\"name\":\"customer_name\",\"type\":\"string\"},{\"name\":\"customer_email\",\"type\":\"string\"},{\"name\":\"customer_address\",\"type\":\"string\"}],\"name\":\"Customer\",\"namespace\":\"io.confluent.examples.avro\",\"type\":\"record\"}"

}'

log "Register schema for product"
curl -X POST http://localhost:8081/subjects/product/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"fields\":[{\"name\":\"product_id\",\"type\":\"int\"},{\"name\":\"product_name\",\"type\":\"string\"},{\"name\":\"product_price\",\"type\":\"double\"}],\"name\":\"Product\",\"namespace\":\"io.confluent.examples.avro\",\"type\":\"record\"}"
}'

log "Register schema for datalake_topic"
curl -X POST http://localhost:8081/subjects/datalake_topic-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]",
    "references": [
      {
        "name": "io.confluent.examples.avro.Customer",
        "subject":  "customer",
        "version": 1
      },
      {
        "name": "io.confluent.examples.avro.Product",
        "subject":  "product",
        "version": 1
      }
    ]
}'

log "Get schema id for datalake_topic"
id=$(curl http://localhost:8081/subjects/customer/versions/1/referencedby | tr -d '[' | tr -d ']')

log "Produce some Customer and Product data in topic datalake_topic"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic datalake_topic --property value.schema.id=$id --property auto.register.schemas=false --property use.latest.version=true << EOF
{ "io.confluent.examples.avro.Product": { "product_id": 1, "product_name" : "rice", "product_price" : 100.00 } }
{ "io.confluent.examples.avro.Customer": { "customer_id": 100, "customer_name": "acme", "customer_email": "acme@google.com", "customer_address": "1 Main St" } }
EOF


log "Creating Data Lake Storage Gen2 Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
            "connector.class": "io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector",
            "tasks.max": "1",
            "topics": "datalake_topic",
            "flush.size": "3",
            "azure.datalake.gen2.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
            "azure.datalake.gen2.client.key": "mypassword",
            "azure.datalake.gen2.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
            "azure.datalake.gen2.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
            "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
            "confluent.license": "",
            "confluent.topic.bootstrap.servers": "broker:9092",
            "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-datalake-gen2-sink/config | jq .


sleep 20

log "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az storage blob list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --container-name topics

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download  --container-name topics --name datalake_topic/partition=0/datalake_topic+0+0000000000.avro --file /tmp/datalake_topic+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

# FIXTHIS:
# Client-Request-ID=c177a74c-1d22-11ec-803d-3e22fbeff495 Retry policy did not allow for a retry: Server-Timestamp=Fri, 24 Sep 2021 10:32:46 GMT, Server-Request-ID=6a414432-b01e-0061-4d2f-b1437f000000, HTTP status code=416, Exception=The range specified is invalid for the current size of the resource. ErrorCode: InvalidRange<?xml version="1.0" encoding="utf-8"?><Error><Code>InvalidRange</Code><Message>The range specified is invalid for the current size of the resource.RequestId:6a414432-b01e-0061-4d2f-b1437f000000Time:2021-09-24T10:32:46.9531674Z</Message></Error>.
# {
#   "content": null,
#   "deleted": false,
#   "metadata": {},
#   "name": "datalake_topic/partition=0/datalake_topic+0+0000000000.avro",
#   "properties": {
#     "appendBlobCommittedBlockCount": null,
#     "blobTier": null,
#     "blobTierChangeTime": null,
#     "blobTierInferred": false,
#     "blobType": "BlockBlob",
#     "contentLength": 0,
#     "contentRange": null,
#     "contentSettings": {
#       "cacheControl": null,
#       "contentDisposition": null,
#       "contentEncoding": null,
#       "contentLanguage": null,
#       "contentMd5": null,
#       "contentType": "application/octet-stream"
#     },
#     "copy": {
#       "completionTime": null,
#       "id": null,
#       "progress": null,
#       "source": null,
#       "status": null,
#       "statusDescription": null
#     },
#     "creationTime": "2021-09-24T10:25:31+00:00",
#     "deletedTime": null,
#     "etag": "\"0x8D97F45A2DCA851\"",
#     "lastModified": "2021-09-24T10:25:31+00:00",
#     "lease": {
#       "duration": null,
#       "state": "available",
#       "status": "unlocked"
#     },
#     "pageBlobSequenceNumber": null,
#     "remainingRetentionDays": null,
#     "serverEncrypted": true
#   },
#   "snapshot": null
# }

# file is empty
# ls -lrt /tmp/datalake_topic+0+0000000000.avro
# -rw-r--r--  1 vsaboulin  wheel  0 Sep 24 12:32 /tmp/datalake_topic+0+0000000000.avro

docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/datalake_topic+0+0000000000.avro

exit 0
log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait

log "Deleting active directory app"
az ad app delete --id $AZURE_DATALAKE_CLIENT_ID

