# Google Cloud Functions Sink connector

## Objective

Quickly test [Google Cloud Functions Sink](https://docs.confluent.io/current/connect/kafka-connect-gcp-functions/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* Active Google Cloud Platform (GCP) account with authorization to create resources

## Google Cloud Functions Setup

* Navigate to the [Google Cloud Console](https://console.cloud.google.com/)

* Go to the [Cloud Functions](https://console.cloud.google.com/functions) tab.

![Cloud functions setup](Screenshot1.png)

* Create a new function. Use the default code that is provided.

![Cloud functions setup](Screenshot2.png)

Note down the project id, the region (example `us-central1`), and the function name (example `function-1`) as they will be used later.


## How to run

Simply run:

```bash
$ ./google-cloud-functions.sh <PROJECT> <REGION> <FUNCTION>
```

## Details of what the script is doing

Produce test data to the functions-messages topic in Kafka

```bash
$ docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic functions-messages --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF
```

Creating Google Cloud Functions Sink connector

```bash
$ docker container exec -e PROJECT="$PROJECT" -e REGION="$REGION" -e FUNCTION="$FUNCTION" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "gcp-functions",
               "config": {
                    "connector.class": "io.confluent.connect.gcp.functions.GoogleCloudFunctionsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "functions-messages",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor":1,
                    "function.name": "'"$FUNCTION"'",
                    "project.id": "'"$PROJECT"'",
                    "region": "'"$REGION"'",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "test-error",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.error.topic.key.format": "string",
                    "reporter.error.topic.value.format": "string",
                    "reporter.result.topic.name": "test-result",
                    "reporter.result.topic.key.format": "string",
                    "reporter.result.topic.value.format": "string",
                    "reporter.result.topic.replication.factor": 1
          }}' \
     http://localhost:8083/connectors | jq .
```

Confirm that the messages were delivered to the result topic in Kafka

```bash
$ docker container exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-result --from-beginning --max-messages 3
```

Result:

```
Hello World!
Hello World!
Hello World!
Processed a total of 3 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
