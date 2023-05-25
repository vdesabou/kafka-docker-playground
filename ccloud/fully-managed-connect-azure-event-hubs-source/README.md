# Fully Managed Azure Event Hubs Source connector

## Objective

Quickly test [Azure Event Hubs Source](https://docs.confluent.io/cloud/current/connectors/cc-azure-event-hubs-source.html) connector.


## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## How to run

Simply run:

```
$ playground run -f fully-managed-azure-event-hubs<tab>
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

Creating connector:

```bash
cat << EOF > connector.json
{
    "connector.class": "AzureEventHubsSource",
    "name": "AzureEventHubsSource",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",

    "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
    "azure.eventhubs.sas.key": "$AZURE_SAS_KEY",
    "azure.eventhubs.namespace": "$AZURE_EVENT_HUBS_NAMESPACE",
    "azure.eventhubs.hub.name": "$AZURE_EVENT_HUBS_NAME",
    "kafka.topic": "event_hub_topic",
    "max.events": "50",

    "tasks.max" : "1"
}
EOF

create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300
```


Inject data in Event Hubs, using [simple-send](https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-java-get-started-send) java program

```bash
$ docker exec -d -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_CONNECTION_STRING="$AZURE_EVENT_CONNECTION_STRING" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"
```

Verifying topic `event_hub_topic`

```bash
playground topic consume --topic event_hub_topic --min-expected-messages 2 --timeout 60
```

Results:

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
