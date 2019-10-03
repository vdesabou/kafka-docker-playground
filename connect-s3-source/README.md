# S3 Source connector

## Objective

Quickly test [S3 Source](https://docs.confluent.io/current/connect/kafka-connect-s3-source/index.html) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* `avro-tools` (example `brew install avro-tools`)
* `aws cli`(example `brew install awscli`)

## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` is set, see `docker-compose.yml`file for connect:

```
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:/root/.aws/credentials:ro
```


## How to run

Simply run:

```
$ ./s3.sh <your-bucket-name>
```

## Details of what the script is doing


Steps from [connect-s3-sink](../connect-s3-sink/README.md)


The connector is created with:

```
docker container exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "s3-source3",
               "config": {
                    "tasks.max": "1",
                    "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
                    "s3.region": "us-east-1",
                    "s3.bucket.name": "'"$BUCKET_NAME"'",
                    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "transforms": "AddPrefix",
                    "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.AddPrefix.regex": ".*",
                    "transforms.AddPrefix.replacement": "copy_of_$0"
          }}' \
     http://localhost:8083/connectors | jq .
```

*FIXTHIS*: not working, see https://github.com/confluentinc/kafka-connect-s3-source/pull/45#issuecomment-532587915

```
connect            | [2019-09-26 13:00:53,449] ERROR WorkerSourceTask{id=s3-source3-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
connect            | org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
connect            |    at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:178)
connect            |    at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:104)
connect            |    at org.apache.kafka.connect.runtime.WorkerSourceTask.convertTransformedRecord(WorkerSourceTask.java:284)
connect            |    at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:309)
connect            |    at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:234)
connect            |    at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
connect            |    at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
connect            |    at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
connect            |    at java.util.concurrent.FutureTask.run(FutureTask.java:266)
connect            |    at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
connect            |    at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
connect            |    at java.lang.Thread.run(Thread.java:748)
connect            | Caused by: org.apache.kafka.connect.errors.DataException: Invalid type for STRUCT: class org.apache.avro.generic.GenericData$Record
connect            |    at io.confluent.connect.avro.AvroData.fromConnectData(AvroData.java:619)
connect            |    at io.confluent.connect.avro.AvroData.fromConnectData(AvroData.java:366)
connect            |    at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:80)
connect            |    at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$2(WorkerSourceTask.java:284)
connect            |    at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:128)
connect            |    at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:162)
connect            |    ... 11 more
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
