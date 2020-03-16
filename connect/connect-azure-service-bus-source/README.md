# Azure Service Bus Source connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Azure Service Bus Source](https://docs.confluent.io/current/connect/kafka-connect-azure-servicebus/index.html#servicebus-source-connector-for-cp) connector.


## How to run

Simply run:

```
$ ./azure-service-bus.sh
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the Service Bus setup is automated:

```bash

AZURE_RESOURCE_GROUP=playground$USER
AZURE_SERVICE_BUS_NAMESPACE=playground$USER
AZURE_SERVICE_BUS_QUEUE_NAME=playground$USER
AZURE_REGION=westeurope

# Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
# Creating Azure Service Bus namespace"
az servicebus namespace create \
    --name $AZURE_SERVICE_BUS_NAMESPACE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
# Creating Azure Service Bus Queue"
az servicebus queue create \
    --name $AZURE_SERVICE_BUS_QUEUE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_SERVICE_BUS_NAMESPACE
# Get SAS key for RootManageSharedAccessKey"
AZURE_SAS_KEY=$(az servicebus namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_SERVICE_BUS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryKey')
```

The connector is created with:

```bash
$ docker exec -e AZURE_SERVICE_BUS_QUEUE_NAME="$AZURE_SERVICE_BUS_QUEUE_NAME" -e AZURE_SERVICE_BUS_NAMESPACE="$AZURE_SERVICE_BUS_NAMESPACE" -e AZURE_SAS_KEY="$AZURE_SAS_KEY" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.servicebus.ServiceBusSourceConnector",
                "kafka.topic": "servicebus-topic",
                "tasks.max": "1",
                "azure.servicebus.sas.keyname": "RootManageSharedAccessKey",
                "azure.servicebus.sas.key": "'"$AZURE_SAS_KEY"'",
                "azure.servicebus.namespace": "'"$AZURE_SERVICE_BUS_NAMESPACE"'",
                "azure.servicebus.entity.name": "'"$AZURE_SERVICE_BUS_QUEUE_NAME"'",
                "azure.servicebus.subscription" : "",
                "azure.servicebus.max.message.count" : "10",
                "azure.servicebus.max.waiting.time.seconds" : "30",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-service-bus-source/config | jq .
```

Inject data in Service Bus, using [QueuesGettingStarted](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-cli#send-and-receive-messages) java program

```bash
$ SB_SAMPLES_CONNECTIONSTRING="Endpoint=sb://$AZURE_SERVICE_BUS_NAMESPACE.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=$AZURE_SAS_KEY"
$ docker exec -e SB_SAMPLES_CONNECTIONSTRING="$SB_SAMPLES_CONNECTIONSTRING" -e AZURE_SERVICE_BUS_QUEUE_NAME="$AZURE_SERVICE_BUS_QUEUE_NAME" simple-send bash -c "java -jar queuesgettingstarted-1.0.0-jar-with-dependencies.jar"
```

Verifying topic `servicebus-topic`

```bash
$ timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic servicebus-topic --from-beginning --max-messages 10
```

Results:

```json
{
    "contentType": "application/json",
    "correlationId": null,
    "deadLetterSource": null,
    "deliveryCount": 0,
    "enqueuedTimeUtc": 1584370640,
    "getTo": null,
    "label": "Scientist",
    "lockToken": {
        "string": "b840ea3f-94ac-4085-baba-f03ed929602b"
    },
    "lockedUntilUtc": {
        "long": 1584370700108
    },
    "messageBody": "{\"firstName\":\"Isaac\",\"name\":\"Newton\"}",
    "messageProperties": null,
    "partitionKey": null,
    "replyTo": null,
    "replyToSessionId": null,
    "sequenceNumber": {
        "long": 7
    },
    "sessionId": null,
    "timeToLive": 120000
}
```

Deleting resource group:

```bash
$ az group delete --name $AZURE_RESOURCE_GROUP --yes
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
