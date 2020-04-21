# Azure Event Hubs Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-azure-event-hubs-source/asciinema.gif?raw=true)

## Objective

Quickly test [Azure Event Hubs Source](https://docs.confluent.io/current/connect/kafka-connect-azure-event-hubs/index.html#az-event-hubs-source-connector-for-cp) connector.


## How to run

Simply run:

```
$ ./azure-event-hubs.sh
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the Event Hubs setup is automated:

```bash
AZURE_NAME=playground$USER$TRAVIS_JOB_NUMBER
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
```

The connector is created with:

```bash
$ docker exec -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_HUBS_NAMESPACE="$AZURE_EVENT_HUBS_NAMESPACE" -e AZURE_SAS_KEY="$AZURE_SAS_KEY" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.eventhubs.EventHubsSourceConnector",
                "kafka.topic": "event_hub_topic",
                "tasks.max": "1",
                "max.events": "1",
                "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
                "azure.eventhubs.sas.key": "'"$AZURE_SAS_KEY"'",
                "azure.eventhubs.namespace": "'"$AZURE_EVENT_HUBS_NAMESPACE"'",
                "azure.eventhubs.hub.name": "'"$AZURE_EVENT_HUBS_NAME"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-event-hubs-source/config | jq .
```

Inject data in Event Hubs, using [simple-send](https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend) java program

```bash
$ docker exec -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_HUBS_NAMESPACE="$AZURE_EVENT_HUBS_NAMESPACE" -e AZURE_SAS_KEYNAME="RootManageSharedAccessKey" -e AZURE_SAS_KEY="$AZURE_SAS_KEY" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"
```

Verifying topic `event_hub_topic`

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic event_hub_topic --from-beginning --max-messages 10
```

Deleting resource group:

```bash
$ az group delete --name $AZURE_RESOURCE_GROUP --yes
```

Result:

```
"Message 3"
"Message 0"
"Message 1"
"Message 2"
"Message 7"
"Message 4"
"Message 5"
"Message 6"
"Message 11"
"Message 8"
Processed a total of 10 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
