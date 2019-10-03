# S3 Sink connector

## Objective

Quickly test [S3 Sink](https://docs.confluent.io/current/connect/kafka-connect-s3/index.html#kconnect-long-amazon-s3-sink-connector) connector.

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

The connector is created with:

```
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "s3-sink",
               "config": {
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "s3_topic",
               "s3.region": "us-east-1",
               "s3.bucket.name": "$BUCKET_NAME",
               "s3.part.size": 52428801,
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "NONE"
          }}' \
     http://localhost:8083/connectors | jq .
```

Messages are sent to `s3_topic` topic using:

```
seq -f "{\"f1\": \"value%g\"}" 10 | docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

After a few seconds, S3 should contain files in bucket:

```
$ aws s3api list-objects --bucket "your-bucket-name"

```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
