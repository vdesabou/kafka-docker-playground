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

All the azure functions setup is automated:

```bash
AZURE_NAME=playground$USER$TRAVIS_JOB_NUMBER
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_STORAGE_NAME=$AZURE_NAME
AZURE_FUNCTIONS_NAME=$AZURE_NAME
AZURE_REGION=westeurope

# Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION
$ az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

# Creating storage account $AZURE_STORAGE_NAME in resource $AZURE_RESOURCE_GROUP
$ az storage account create \
    --name $AZURE_STORAGE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS

# Creating local functions project with HTTP trigger
$ docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:3.0-node12-core-tools bash -c "func init LocalFunctionProj --javascript && cd LocalFunctionProj && func new --name HttpExample --template \"HTTP trigger\""

# Creating functions app $AZURE_FUNCTIONS_NAME
$ az functionapp create --consumption-plan-location $AZURE_REGION --name $AZURE_FUNCTIONS_NAME --resource-group $AZURE_RESOURCE_GROUP --runtime node --storage-account $AZURE_STORAGE_NAME --runtime-version 10 --functions-version 3

# Publishing functions app
$ docker run -v $PWD/LocalFunctionProj:/LocalFunctionProj mcr.microsoft.com/azure-functions/node:3.0-node12-core-tools bash -c "az login -u \"$AZ_USER\" -p \"$AZ_PASS\" && cd LocalFunctionProj && func azure functionapp publish \"$AZURE_FUNCTIONS_NAME\""
```

Sending messages to topic functions-test

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic functions-test --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF
```

Creating Azure Functions Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.functions.AzureFunctionsSinkConnector",
                "tasks.max": "1",
                "topics": "functions-test",
                "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                "value.converter":"org.apache.kafka.connect.storage.StringConverter",
                "function.url": "'"$FUNCTIONS_URL"'",
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
     http://localhost:8083/connectors/azure-functions-sink/config | jq .
```

Confirm that the messages were delivered to the result topic in Kafka

```bash
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-result --from-beginning --max-messages 3
```

Results:

```
This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.
This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.
This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.
Processed a total of 3 messages
```

Deleting resource group:

```bash
$ az group delete --name $AZURE_RESOURCE_GROUP --yes
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
