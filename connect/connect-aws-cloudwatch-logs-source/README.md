# AWS CloudWatch Logs Source connector



## Objective

Quickly test [AWS CloudWatch Logs](https://docs.confluent.io/current/connect/kafka-connect-aws-cloudwatch-logs/index.html#kconnect-long-aws-cloudwatch-logs-source-connector) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

## How to run

Simply run:

```bash
$ playground run -f cloudwatch<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

If you want to assume IAM roles:

```
$ playground run -f cloudwatch-with-assuming-iam-role<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> (in that case `~/.aws/credentials-with-assuming-iam-role` file must be set)
```


## Details of what the script is doing

Create a log group in AWS CloudWatch Logs.

```bash
$ aws logs create-log-group --log-group-name my-log-group
```

Create a log stream in AWS CloudWatch Logs.

```bash
$ aws logs create-log-stream --log-group-name my-log-group --log-stream my-log-stream
```

Insert Records into your log stream.

Note: If this is the first time inserting logs into a new log stream, then no sequence token is needed.
However, after the first put, there will be a sequence token returned that will be needed as a parameter in the next put.

```bash
$ aws logs put-log-events --log-group-name my-log-group --log-stream my-log-stream --log-events timestamp=`date +%s000`,message="This is a log #0"
```

Injecting more messages

```bash
for i in $(seq 1 10)
do
     token=$($ aws logs describe-log-streams --log-group-name my-log-group | jq -r .logStreams[0].uploadSequenceToken)
     $ aws logs put-log-events --log-group-name my-log-group --log-stream my-log-stream --log-events timestamp=`date +%s000`,message="This is a log #${i}" --sequence-token ${token}
done
```

Creating AWS CloudWatch Logs Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector",
               "tasks.max": "1",
               "aws.cloudwatch.logs.url": "$CLOUDWATCH_LOGS_URL",
               "aws.cloudwatch.log.group": "$LOG_GROUP",
               "aws.cloudwatch.log.streams": "$LOG_STREAM",
               "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
               "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-cloudwatch-logs-source/config | jq .
```

Verify we have received the data in `my-log-group.my-log-stream` topic

```bash
playground topic consume --topic my-log-group.my-log-stream --min-expected-messages 10 --timeout 60
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
