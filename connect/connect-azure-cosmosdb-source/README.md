# Azure Cosmos DB Source connector



## Objective

Quickly test [Azure Cosmos DB Source](https://github.com/microsoft/kafka-connect-cosmosdb) connector.


## How to run

Simply run:

```
$ just use <playground run> command and search for azure-cosmosdb-source.sh in this folder
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the Cosmos DB setup is automated:

```bash
AZURE_NAME=pg${USER}cs${GITHUB_RUN_NUMBER}${TAG}
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
$ TOPIC_MAP="apparels#${AZURE_COSMOSDB_DB_NAME}"

$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "com.azure.cosmos.kafka.connect.source.CosmosDBSourceConnector",
                "tasks.max": "1",
                "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "key.converter.schemas.enable": "false",
                "connect.cosmos.task.poll.interval": "100",
                "connect.cosmos.connection.endpoint": "${file:/data:AZURE_COSMOSDB_DB_ENDPOINT_URI}",
                "connect.cosmos.master.key": "${file:/data:AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY}",
                "connect.cosmos.databasename": "${file:/data:AZURE_COSMOSDB_DB_NAME}",
                "connect.cosmos.containers.topicmap": "${file:/data:TOPIC_MAP}",
                "connect.cosmos.offset.useLatest": false,
                "errors.tolerance": "all",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/azure-cosmosdb-source/config | jq .
```

Messages are sent to Cosmos DB using python script:

```bash
$ docker exec -e AZURE_COSMOSDB_DB_ENDPOINT_URI=$AZURE_COSMOSDB_DB_ENDPOINT_URI -e AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY=$AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY -e AZURE_COSMOSDB_DB_NAME=$AZURE_COSMOSDB_DB_NAME -e AZURE_COSMOSDB_CONTAINER_NAME=$AZURE_COSMOSDB_CONTAINER_NAME azure-cosmos-client bash -c "python /insert-data.py"
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

for i in range(1, 10):
    container.upsert_item({
            'id': 'item{0}'.format(i),
            'productName': 'Widget',
            'productModel': 'Model {0}'.format(i)
        }
    )
```

Verifying topic apparels:

```bash
playground topic consume --topic apparels --min-expected-messages 9 --timeout 60
```

Results:

```json
{"id":"item1","productName":"Widget","productModel":"Model 1","_rid":"KnksAPa6jwEBAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEBAAAAAAAAAA==/","_etag":"\"0000f815-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":3}
{"id":"item2","productName":"Widget","productModel":"Model 2","_rid":"KnksAPa6jwECAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwECAAAAAAAAAA==/","_etag":"\"0000f915-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":4}
{"id":"item3","productName":"Widget","productModel":"Model 3","_rid":"KnksAPa6jwEDAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEDAAAAAAAAAA==/","_etag":"\"0000fa15-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":5}
{"id":"item4","productName":"Widget","productModel":"Model 4","_rid":"KnksAPa6jwEEAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEEAAAAAAAAAA==/","_etag":"\"0000fb15-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":6}
{"id":"item5","productName":"Widget","productModel":"Model 5","_rid":"KnksAPa6jwEFAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEFAAAAAAAAAA==/","_etag":"\"0000fc15-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":7}
{"id":"item6","productName":"Widget","productModel":"Model 6","_rid":"KnksAPa6jwEGAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEGAAAAAAAAAA==/","_etag":"\"0000fd15-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":8}
{"id":"item7","productName":"Widget","productModel":"Model 7","_rid":"KnksAPa6jwEHAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEHAAAAAAAAAA==/","_etag":"\"0000fe15-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":9}
{"id":"item8","productName":"Widget","productModel":"Model 8","_rid":"KnksAPa6jwEIAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEIAAAAAAAAAA==/","_etag":"\"0000ff15-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":10}
{"id":"item9","productName":"Widget","productModel":"Model 9","_rid":"KnksAPa6jwEJAAAAAAAAAA==","_self":"dbs/KnksAA==/colls/KnksAPa6jwE=/docs/KnksAPa6jwEJAAAAAAAAAA==/","_etag":"\"00000016-0000-0d00-0000-6076dab50000\"","_attachments":"attachments/","_ts":1618401973,"_lsn":11}
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
