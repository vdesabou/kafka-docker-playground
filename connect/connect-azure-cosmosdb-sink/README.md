# Azure Cosmos DB Sink connector



## Objective

Quickly test [Azure Cosmos DB Sink](https://github.com/microsoft/kafka-connect-cosmosdb) connector.


## How to run

Simply run:

```
$ just use <playground run> command and search for azure-cosmosdb-sink.sh in this folder
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the Cosmos DB setup is automated:

```bash
AZURE_NAME=pg${USER}ck${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_REGION=westeurope
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_COSMOSDB_SERVER_NAME=$AZURE_NAME
AZURE_COSMOSDB_DB_NAME=$AZURE_NAME
AZURE_COSMOSDB_CONTAINER_NAME=$AZURE_NAME

# Creating Azure Resource Group $AZURE_RESOURCE_GROUP
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

# Creating Cosmos DB server $AZURE_COSMOSDB_SERVER_NAME
az cosmosdb create \
    --name $AZURE_COSMOSDB_SERVER_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --locations regionName=$AZURE_REGION

# Create the database
az cosmosdb sql database create \
    --name $AZURE_COSMOSDB_DB_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --account-name $AZURE_COSMOSDB_SERVER_NAME \
    --throughput 400

# Create the container
az cosmosdb sql container create \
    --name $AZURE_COSMOSDB_CONTAINER_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --account-name $AZURE_COSMOSDB_SERVER_NAME \
    --database-name $AZURE_COSMOSDB_DB_NAME \
    --partition-key-path "/id"

# With the Azure Cosmos DB instance setup, you will need to get the Cosmos DB endpoint URI and primary connection key. These values will be used to setup the Cosmos DB Source and Sink connectors.
AZURE_COSMOSDB_DB_ENDPOINT_URI="https://${AZURE_COSMOSDB_DB_NAME}.documents.azure.com:443/"
# get Cosmos DB primary connection key
AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY=$(az cosmosdb keys list -n $AZURE_COSMOSDB_DB_NAME -g $AZURE_RESOURCE_GROUP --query primaryMasterKey -o tsv)
```

The connector is created with:

```bash
$ TOPIC_MAP="hotels#${AZURE_COSMOSDB_DB_NAME}"

$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "com.azure.cosmos.kafka.connect.sink.CosmosDBSinkConnector",
                "tasks.max": "1",
                "topics": "hotels",
                "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "key.converter.schemas.enable": "false",
                "connect.cosmos.connection.endpoint": "${file:/data:AZURE_COSMOSDB_DB_ENDPOINT_URI}",
                "connect.cosmos.master.key": "${file:/data:AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY}",
                "connect.cosmos.databasename": "${file:/data:AZURE_COSMOSDB_DB_NAME}",
                "connect.cosmos.containers.topicmap": "${file:/data:TOPIC_MAP}",
          }' \
     http://localhost:8083/connectors/azure-cosmosdb-sink/config | jq .
```

Write data to topic hotels:

```bash
$ playground topic produce -t hotels --nb-messages 1 << 'EOF'
{"id": "h1", "HotelName": "Marriott", "Description": "Marriott description"}
{"id": "h2", "HotelName": "HolidayInn", "Description": "HolidayInn description"}
{"id": "h3", "HotelName": "Motel8", "Description": "Motel8 description"}
EOF
```

Messages are received from Cosmos DB using python script:

```bash
$ docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI=$AZURE_COSMOSDB_DB_ENDPOINT_URI -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY=$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY -e AZURE_COSMOSDB_DB_NAME=$AZURE_COSMOSDB_DB_NAME -e AZURE_COSMOSDB_CONTAINER_NAME=$AZURE_COSMOSDB_CONTAINER_NAME azure-cosmos-client bash -c "python /get-data.py"
```

```python
from azure.cosmos import CosmosClient

import os

url = os.environ['AZURE_COSMOSDB_DB_ENDPOINT_URI']
key = os.environ['AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY']
database_name = os.environ['AZURE_COSMOSDB_DB_NAME']
container_name = os.environ['AZURE_COSMOSDB_CONTAINER_NAME']
client = CosmosClient(url, credential=key)
database = client.get_database_client(database_name)
container = database.get_container_client(container_name)

# Enumerate the returned items
import json
for item in container.query_items(
        query='SELECT * FROM '+container_name+' r',
        enable_cross_partition_query=True):
    print(json.dumps(item, indent=True))
```

Results:

```json
{
 "Description": "Marriott description",
 "id": "h1",
 "HotelName": "Marriott",
 "_rid": "5dodALYgtP8BAAAAAAAAAA==",
 "_self": "dbs/5dodAA==/colls/5dodALYgtP8=/docs/5dodALYgtP8BAAAAAAAAAA==/",
 "_etag": "\"1b0036f1-0000-0d00-0000-6076f04d0000\"",
 "_attachments": "attachments/",
 "_ts": 1618407501
}
{
 "Description": "HolidayInn description",
 "id": "h2",
 "HotelName": "HolidayInn",
 "_rid": "5dodALYgtP8CAAAAAAAAAA==",
 "_self": "dbs/5dodAA==/colls/5dodALYgtP8=/docs/5dodALYgtP8CAAAAAAAAAA==/",
 "_etag": "\"1b0037f1-0000-0d00-0000-6076f04d0000\"",
 "_attachments": "attachments/",
 "_ts": 1618407501
}
{
 "Description": "Motel8 description",
 "id": "h3",
 "HotelName": "Motel8",
 "_rid": "5dodALYgtP8DAAAAAAAAAA==",
 "_self": "dbs/5dodAA==/colls/5dodALYgtP8=/docs/5dodALYgtP8DAAAAAAAAAA==/",
 "_etag": "\"1b0038f1-0000-0d00-0000-6076f04d0000\"",
 "_attachments": "attachments/",
 "_ts": 1618407501
}
```

Delete Cosmos DB instance:

```bash
az cosmosdb delete -g $AZURE_RESOURCE_GROUP -n $AZURE_COSMOSDB_SERVER_NAME --yes
```

Deleting resource group:

```bash
az group delete --name $AZURE_RESOURCE_GROUP --yes
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
