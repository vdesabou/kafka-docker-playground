# AWS Kinesis Source connector



## Objective

Quickly test [Kinesis Connector](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#quick-start) connector.

## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

Example:

```
[default]
aws_access_key_id=xxx
aws_secret_access_key=xxx
region=eu-west-3
```

Make sure that region corresponds to the one used by the test (eu-west-3 by default), otherwise the conector will fail to start with `Stream does not exist`.

## How to run

Simply run:

```
$ playground run -f kinesis-source<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

If you want to assume IAM roles:

```
$ playground run -f kinesis-source-with-assuming-iam-role<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*> (in that case `~/.aws/credentials-with-assuming-iam-role` file must be set)
```

or with AssumeRole using custom AWS credentials provider (⚠️ custom code is just an example, there is no support for it):

```
$ playground run -f kinesis-source-with-assuming-iam-role<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

## Details of what the script is doing

Create a Kinesis stream `kafka_docker_playground` in $AWS_REGION region:

```
$ aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1 --region $AWS_REGION
```

Insert records in Kinesis stream:

```
$ aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1 --region $AWS_REGION
```

The connector is created with:

```
playground connector create-or-update --connector kinesis-source << EOF
{
        "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.stream": "$KINESIS_STREAM_NAME",
               "confluent.license": "",
               "name": "kinesis-source",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF
```

Verify we have received the data in kinesis_topic topic:

```
playground topic consume --topic kinesis_topic --min-expected-messages 1 --timeout 60
```

Delete your stream and clean up resources to avoid incurring any unintended charges:

```
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
