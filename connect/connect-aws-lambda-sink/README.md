# AWS Lambda Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-lambda-sink/asciinema.gif?raw=true)

## Objective

Quickly test [AWS Lambda](https://docs.confluent.io/current/connect/kafka-connect-aws-lambda/index.html#kconnect-long-lambda-sink-connector) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set, see `docker-compose.yml`file for connect:

```yaml
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:$CONNECT_CONTAINER_HOME_DIR/.aws/credentials
        - $HOME/.aws/config:$CONNECT_CONTAINER_HOME_DIR/.aws/config
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
$ seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'
```

Creating AWS Lambda Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
                    "tasks.max": "1",
                    "topics" : "add-topic",
                    "aws.lambda.function.name" : "Add",
                    "aws.lambda.invocation.type" : "sync",
                    "aws.lambda.batch.size" : "50",
                    "aws.lambda.region": "us-east-1",
                    "behavior.on.error" : "fail",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-lambda/config | jq .
```

Verifying topic `add-topic-response`

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 10
```

Results:

```json
"{\"timestamp\":1598334450575,\"offset\":0,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":2}}"
"{\"timestamp\":1598334450609,\"offset\":1,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":3}}"
"{\"timestamp\":1598334450609,\"offset\":2,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":4}}"
"{\"timestamp\":1598334450609,\"offset\":3,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":5}}"
"{\"timestamp\":1598334450610,\"offset\":4,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":6}}"
"{\"timestamp\":1598334450610,\"offset\":5,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":7}}"
"{\"timestamp\":1598334450610,\"offset\":6,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":8}}"
"{\"timestamp\":1598334450611,\"offset\":7,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":9}}"
"{\"timestamp\":1598334450611,\"offset\":8,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":10}}"
"{\"timestamp\":1598334450611,\"offset\":9,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":11}}"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
