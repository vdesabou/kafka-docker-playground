#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

login_and_maybe_set_azure_subscription

AZURE_NAME=pgfm${USER}s${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SEARCH_SERVICE_NAME=$AZURE_NAME
AZURE_REGION=westeurope
AZURE_AD_APP=pgfm${USER}

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
log "Creating Azure Search service"
az search service create \
    --name $AZURE_SEARCH_SERVICE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Basic
AZURE_SEARCH_ADMIN_PRIMARY_KEY=$(az search admin-key show \
    --resource-group $AZURE_RESOURCE_GROUP \
    --service-name $AZURE_SEARCH_SERVICE_NAME | jq -r '.primaryKey')

subscriptionId=$(az account list --query "[?isDefault].id" | jq -r '.[0]')
tenantId=$(az account list --query "[?isDefault].tenantId" | jq -r '.[0]')
# https://docs.confluent.io/cloud/current/connectors/cc-azure-cognitive-search-sink.html#az-service-principal
appId=$(az ad sp create-for-rbac --name $AZURE_AD_APP --role Contributor --scopes /subscriptions/$subscriptionId/resourceGroups/$AZURE_RESOURCE_GROUP --output json | jq -r '.appId')
appPassword=$(az ad sp create-for-rbac --name $AZURE_AD_APP --role Contributor --scopes /subscriptions/$subscriptionId/resourceGroups/$AZURE_RESOURCE_GROUP --output json | jq -r '.password')

log "Creating Azure Search index"
curl -X POST \
"https://${AZURE_SEARCH_SERVICE_NAME}.search.windows.net/indexes?api-version=2019-05-06" \
-H 'Accept: application/json' \
-H 'Content-Type: application/json' \
-H "api-key: $AZURE_SEARCH_ADMIN_PRIMARY_KEY" \
-d '{
  "name": "hotels-sample-index",
  "fields": [
    {"name": "HotelId", "type": "Edm.String", "key": true, "searchable": false, "sortable": false, "facetable": false},
    {"name": "Description", "type": "Edm.String", "filterable": false, "sortable": false, "facetable": false},
    {"name": "HotelName", "type": "Edm.String", "facetable": false}
  ]
}'

bootstrap_ccloud_environment

set +e
playground topic delete --topic hotels-sample
sleep 3
playground topic create --topic hotels-sample --nb-partitions 1
set -e

log "Sending messages to topic hotels-sample"
playground topic produce -t hotels-sample --nb-messages 1 --forced-value '{"HotelName": "Marriott", "Description": "Marriott description"}' --key "marriottId" << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "HotelName",
      "type": "string"
    },
    {
      "name": "Description",
      "type": "string"
    }
  ]
}
EOF
playground topic produce -t hotels-sample --nb-messages 1 --forced-value '{"HotelName": "HolidayInn", "Description": "HolidayInn description"}' --key "holidayinnId" << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "HotelName",
      "type": "string"
    },
    {
      "name": "Description",
      "type": "string"
    }
  ]
}
EOF
playground topic produce -t hotels-sample --nb-messages 1 --forced-value '{"HotelName": "Motel8", "Description": "motel8 description"}' --key "motel8Id" << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "HotelName",
      "type": "string"
    },
    {
      "name": "Description",
      "type": "string"
    }
  ]
}
EOF


connector_name="AzureCognitiveSearchSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureCognitiveSearchSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "hotels-sample",
    "azure.search.service.name": "$AZURE_SEARCH_SERVICE_NAME",
    "azure.search.api.key": "$AZURE_SEARCH_ADMIN_PRIMARY_KEY",
    "azure.search.resourcegroup.name": "$AZURE_RESOURCE_GROUP",
    "index.name": "\${topic}-index",
    "azure.search.client.id": "$appId",
    "azure.search.client.secret": "$appPassword",
    "azure.search.tenant.id": "$tenantId",
    "azure.search.subscription.id": "$subscriptionId",
    "input.data.format": "AVRO",

    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 30

log "Searching Azure Search index"
curl -X GET \
"https://${AZURE_SEARCH_SERVICE_NAME}.search.windows.net/indexes/hotels-sample-index/docs?api-version=2019-05-06&search=*" \
-H 'Content-Type: application/json' \
-H "api-key: $AZURE_SEARCH_ADMIN_PRIMARY_KEY" | jq . > /tmp/result.log  2>&1

cat /tmp/result.log
grep "Marriott" /tmp/result.log
grep "HolidayInn" /tmp/result.log
grep "Motel8" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name