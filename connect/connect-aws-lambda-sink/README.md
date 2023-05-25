# AWS Lambda Sink connector



## Objective

Quickly test [AWS Lambda](https://docs.confluent.io/current/connect/kafka-connect-aws-lambda/index.html#kconnect-long-lambda-sink-connector) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

## How to run

Simply run:

```bash
$ playground run -f lambda<tab>
```

If you want to assume IAM roles:

```
$ playground run -f lambda-sink-with-assuming-iam-role<tab> (in that case `~/.aws/credentials-with-assuming-iam-role` file must be set)
```

## Details of what the script is doing

Creating AWS role

```bash
LAMBDA_ROLE_NAME=playground_lambda_role$TAG
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME//[-.]/}

LAMBDA_ROLE=$(aws iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' --output text --query 'Role.Arn')
```

Creating AWS Lambda function

```bash
LAMBDA_FUNCTION_NAME=playground_lambda_function$TAG
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME//[-.]/}

cd ${DIR}/my-add-function
rm -f add.zip
zip add.zip add.py
cp add.zip /tmp/
aws lambda create-function --function-name $LAMBDA_FUNCTION_NAME --zip-file fileb:///tmp/add.zip --handler add.lambda_handler --runtime python3.8 --role $LAMBDA_ROLE
cd -
```

`./my-add-function/add.py` is the python function used:

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
               "aws.lambda.function.name" : "'"$LAMBDA_FUNCTION_NAME"'",
               "aws.lambda.invocation.type" : "sync",
               "aws.lambda.batch.size" : "50",
               "aws.lambda.region": "'"$AWS_REGION"'",
               "aws.access.key.id" : "'"$AWS_ACCESS_KEY_ID"'",
               "aws.secret.access.key": "'"$AWS_SECRET_ACCESS_KEY"'",
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
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60
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
