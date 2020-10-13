# Azure Functions Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-azure-functions-sink/asciinema.gif?raw=true)

## Objective

Quickly test [Azure Functions Sink](https://docs.confluent.io/current/connect/kafka-connect-azure-functions/index.html#quick-start) connector.




## How to run

Simply run:

```
$ ./azure-functions.sh
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the blob storage setup is automated:

```bash
AZURE_NAME=playground$USER$TRAVIS_JOB_NUMBER
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SEARCH_SERVICE_NAME=$AZURE_NAME
AZURE_REGION=westeurope

# Creating Azure Resource Group $AZURE_RESOURCE_GROUP
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
# Creating Azure Search service
az search service create \
    --name $AZURE_SEARCH_SERVICE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku free
AZURE_SEARCH_ADMIN_PRIMARY_KEY=$(az search admin-key show \
    --resource-group $AZURE_RESOURCE_GROUP \
    --service-name $AZURE_SEARCH_SERVICE_NAME | jq -r '.primaryKey')
```

Creating Azure Search index

```bash
$ curl -X POST \
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
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.search.AzureSearchSinkConnector",
                "tasks.max": "1",
                "topics": "hotels-sample",
                "key.converter": "io.confluent.connect.avro.AvroConverter",
                "key.converter.schema.registry.url": "http://schema-registry:8081",
                "value.converter": "io.confluent.connect.avro.AvroConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "azure.search.service.name": "'"$AZURE_SEARCH_SERVICE_NAME"'",
                "azure.search.api.key": "'"$AZURE_SEARCH_ADMIN_PRIMARY_KEY"'",
                "index.name": "${topic}-index",
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
     http://localhost:8083/connectors/azure-search/config | jq .
```

Messages are sent to `hotels-sample` topic using:

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic hotels-sample --property key.schema='{"type":"string"}' --property "parse.key=true" --property "key.separator=," --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"HotelName","type":"string"},{"name":"Description","type":"string"}]}' << EOF
"marriotId",{"HotelName": "Marriot", "Description": "Marriot description"}
"holidayinnId",{"HotelName": "HolidayInn", "Description": "HolidayInn description"}
"motel8Id",{"HotelName": "Motel8", "Description": "motel8 description"}
EOF
```

Searching Azure Search index

```bash
$ curl -X GET \
"https://${AZURE_SEARCH_SERVICE_NAME}.search.windows.net/indexes/hotels-sample-index/docs?api-version=2019-05-06&search=*" \
-H 'Content-Type: application/json' \
-H "api-key: $AZURE_SEARCH_ADMIN_PRIMARY_KEY" | jq
```

Results:

```json
{
  "@odata.context": "https://playgroundvsaboulin.search.windows.net/indexes('hotels-sample-index')/$metadata#docs(*)",
  "value": [
    {
      "@search.score": 1,
      "HotelId": "marriotId",
      "Description": "Marriot description",
      "HotelName": "Marriot"
    },
    {
      "@search.score": 1,
      "HotelId": "holidayinnId",
      "Description": "HolidayInn description",
      "HotelName": "HolidayInn"
    },
    {
      "@search.score": 1,
      "HotelId": "motel8Id",
      "Description": "motel8 description",
      "HotelName": "Motel8"
    }
  ]
}
```

Deleting resource group:

```bash
$ az group delete --name $AZURE_RESOURCE_GROUP --yes
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
