# S3 Source connector

## Objective

Quickly test [S3 Source](https://docs.confluent.io/current/connect/kafka-connect-s3-source/index.html) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

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

```bash
$ ./s3.sh <your-bucket-name>
```

## Details of what the script is doing


Steps from [connect-s3-sink](connect/connect-s3-sink/README.md)


The connector is created with:

```bash
$ docker exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/s3-source/config | jq .
```

Verifying topic `copy_of_s3_topic`

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic copy_of_s3_topic --from-beginning --max-messages 9
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

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
