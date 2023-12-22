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
    az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
else
    log "Logging to Azure using browser"
    az login
fi

AZURE_NAME=pg${USER}s${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SEARCH_SERVICE_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER
log "Creating Azure Search service"
az search service create \
    --name $AZURE_SEARCH_SERVICE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Basic
AZURE_SEARCH_ADMIN_PRIMARY_KEY=$(az search admin-key show \
    --resource-group $AZURE_RESOURCE_GROUP \
    --service-name $AZURE_SEARCH_SERVICE_NAME | jq -r '.primaryKey')


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

# generate data file for externalizing secrets
sed -e "s|:AZURE_SEARCH_SERVICE_NAME:|$AZURE_SEARCH_SERVICE_NAME|g" \
    -e "s|:AZURE_SEARCH_ADMIN_PRIMARY_KEY:|$AZURE_SEARCH_ADMIN_PRIMARY_KEY|g" \
    ../../connect/connect-azure-cognitive-search-sink/data.template > ../../connect/connect-azure-cognitive-search-sink/data

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

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


log "Creating Azure Search Sink connector"
playground connector create-or-update --connector azure-cognitive-search << EOF
{
    "connector.class": "io.confluent.connect.azure.search.AzureSearchSinkConnector",
    "tasks.max": "1",
    "topics": "hotels-sample",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "azure.search.service.name": "\${file:/data:AZURE_SEARCH_SERVICE_NAME}",
    "azure.search.api.key": "\${file:/data:AZURE_SEARCH_ADMIN_PRIMARY_KEY}",
    "proxy.host": "nginx-proxy",
    "proxy.port": "8888",
    "index.name": "\${topic}-index",
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

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
