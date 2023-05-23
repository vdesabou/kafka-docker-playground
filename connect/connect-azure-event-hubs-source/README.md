# Azure Event Hubs Source connector



## Objective

Quickly test [Azure Event Hubs Source](https://docs.confluent.io/current/connect/kafka-connect-azure-event-hubs/index.html#az-event-hubs-source-connector-for-cp) connector.


## How to run

Simply run:

```
$ playground run -f azure-event-hubs<tab>
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the Event Hubs setup is automated:

```bash
AZURE_NAME=pg${USER}eh${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_EVENT_HUBS_NAMESPACE=$AZURE_NAME
AZURE_EVENT_HUBS_NAME=$AZURE_NAME
AZURE_REGION=westeurope

# Creating Azure Resource Group $AZURE_RESOURCE_GROUP
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
# Creating Azure Event Hubs namespace
az eventhubs namespace create \
    --name $AZURE_EVENT_HUBS_NAMESPACE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --enable-kafka true
# Creating Azure Event Hubs
az eventhubs eventhub create \
    --name $AZURE_EVENT_HUBS_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE
# Get SAS key for RootManageSharedAccessKey
AZURE_SAS_KEY=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryKey')
#Get Connection String for SimpleSend client
AZURE_EVENT_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryConnectionString')
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.eventhubs.EventHubsSourceConnector",
                "kafka.topic": "event_hub_topic",
                "tasks.max": "1",
                "max.events": "1",
                "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
                "azure.eventhubs.sas.key": "${file:/data:AZURE_SAS_KEY}",
                "azure.eventhubs.namespace": "${file:/data:AZURE_EVENT_HUBS_NAMESPACE}",
                "azure.eventhubs.hub.name": "${file:/data:AZURE_EVENT_HUBS_NAME}",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-event-hubs-source/config | jq .
```

Inject data in Event Hubs, using [simple-send](https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-java-get-started-send) java program

```bash
$ docker exec -d -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_CONNECTION_STRING="$AZURE_EVENT_CONNECTION_STRING" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"
```

Verifying topic `event_hub_topic`

```bash
playground topic consume --topic event_hub_topic --expected-messages 2
```

Deleting resource group:

```bash
$ az group delete --name $AZURE_RESOURCE_GROUP --yes
```

Result:

```
mykey   Foo
mykey   Bar
Processed a total of 2 messages
```

```json
[
    {
        "__confluent_index": 0,
        "headers": [
            {
                "key": "x-opt-sequence-number",
                "stringValue": "0"
            },
            {
                "key": "x-opt-enqueued-time",
                "stringValue": "2022-01-24T16:19:51.662Z"
            },
            {
                "key": "x-opt-offset",
                "stringValue": "0"
            },
            {
                "key": "x-opt-partition-key",
                "stringValue": "mykey"
            },
            {
                "key": "azure.eventhubs.namespace",
                "stringValue": "pgec2usereh701"
            },
            {
                "key": "azure.eventhubs.hub.name",
                "stringValue": "pgec2usereh701"
            },
            {
                "key": "azure.eventhubs.partition.id",
                "stringValue": "3"
            },
            {
                "key": "system.properties",
                "stringValue": "{}"
            },
            {
                "key": "properties",
                "stringValue": "{}"
            }
        ],
        "key": "mykey",
        "offset": 0,
        "partition": 0,
        "timestamp": 1643041191662,
        "timestampType": "CREATE_TIME",
        "topic": "event_hub_topic",
        "value": "\u0000\u0000\u0000\u0000\u0001Foo"
    }
]
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
