# AWS Lambda Sink connector

## Objective

Quickly test [AWS Lambda](https://docs.confluent.io/current/connect/kafka-connect-aws-lambda/index.html#kconnect-long-lambda-sink-connector) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set, see `docker-compose.yml`file for connect:

```yaml
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:/root/.aws/credentials:ro
        - $HOME/.aws/config:/root/.aws/config:ro
```

Create an AWS Lambda function with name **Add** and use the below given python script

Sample function in python to add two numbers and return the result:

```python
import json
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    result_list = []
    for obj in event:

        payload = obj["payload"]
        logging.info(payload)

        value = payload["value"]
        num1 = value["a"]
        num2 = value["b"]

        timestamp = payload["timestamp"]
        offset = payload["offset"]
        partition = payload["partition"]
        topic = payload["topic"]

        payload_result = {}

        payload_result["timestamp"] = timestamp
        payload_result["offset"] = offset
        payload_result["partition"] = partition
        payload_result["topic"] = topic

        result = {}
        result["sum"] = num1 + num2
        payload_result["result"] = result

        final_result = {}
        final_result["payload"] = payload_result

        result_list.append(final_result)

        logging.info(final_result)
    return result_list
```

## How to run

Simply run:

```bash
$ ./lambda.sh
```


## Details of what the script is doing

Sending messages to topic `add-topic`

```bash
$ seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'
```

Creating AWS Lambda Sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
                    "tasks.max": "1",
                    "topics" : "add-topic",
                    "aws.lambda.function.name" : "Add",
                    "aws.lambda.invocation.type" : "sync",
                    "aws.lambda.batch.size" : "50",
                    "behavior.on.error" : "fail",
                    "aws.lambda.response.topic": "add-topic-response",
                    "aws.lambda.response.bootstrap.servers": "broker:9092",
                    "aws.lambda.response.client.id": "add-topic-response-client",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-lambda/config | jq .
```

Verifying topic `add-topic-response`

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic add-topic-response --from-beginning --max-messages 1
```

Results:

```json
{
    "offset": 0,
    "partition": 0,
    "result": {
        "sum": 2
    },
    "timestamp": 1574851464813,
    "topic": "add-topic"
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
