# S3 Source connector



## Objective

Quickly test [S3 Source](https://docs.confluent.io/kafka-connect-s3-source/current/) connector.


## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.


## How to run

Simply run:

For [Backup and Restore Amazon S3 Source](https://docs.confluent.io/kafka-connect-s3-source/current/backup-and-restore/overview.html#):

```bash
$ just use <playground run> command and search for s3-source-backup-and-restore.sh in this folder
```

For [Generalized Amazon S3 Source](https://docs.confluent.io/kafka-connect-s3-source/current/generalized/overview.html) (it requires version 2.0.0 at minimum):

```bash
$ just use <playground run> command and search for s3-source-generalized.sh in this folder
```

If you want to assume IAM roles:

```
$ just use <playground run> command and search for s3-source-backup-and-restore-with-assuming-iam-role.sh in this folder
```

or with AssumeRole using custom AWS credentials provider (⚠️ custom code is just an example, there is no support for it):

```
$ just use <playground run> command and search for s3-source-backup-and-restore-assuming-iam-role-with-custom-aws-credential-provider.sh in this folder
```

## Details of what the script is doing

### Backup and Restore Amazon S3 Source

Steps from [connect-aws-s3-sink](connect/connect-aws-s3-sink/README.md)

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "$AWS_REGION",
               "s3.bucket.name": "$AWS_BUCKET_NAME",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex": ".*",
               "transforms.AddPrefix.replacement": "copy_of_\$0"
          }' \
     http://localhost:8083/connectors/s3-source/config | jq .
```

Verifying topic `copy_of_s3_topic`

```bash
playground topic consume --topic copy_of_s3_topic --min-expected-messages 9 --timeout 60
```

Results:

```
value1

value2

value3

value4

value5

value6

value7

value8

value9
Processed a total of 9 messages
```

### Generalized Amazon S3 Source

Copy `generalized.quickstart.json` to bucket `$AWS_BUCKET_NAME/quickstart`:

```bash
aws s3 cp generalized.quickstart.json s3://$AWS_BUCKET_NAME/quickstart/generalized.quickstart.json
```

Creating Generalized S3 Source connector with bucket name `<$AWS_BUCKET_NAME>`:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "$AWS_REGION",
               "s3.bucket.name": "$AWS_BUCKET_NAME",
               "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "confluent.license": "",
               "mode": "GENERIC",
               "topics.dir": "quickstart",
               "topic.regex.list": "quick-start-topic:.*",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/s3-source-generalized/config | jq .
```

Verifying topic `quick-start-topic`:

```bash
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
{"f1":"value4"}
{"f1":"value5"}
{"f1":"value6"}
{"f1":"value7"}
{"f1":"value8"}
{"f1":"value9"}
Processed a total of 9 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
