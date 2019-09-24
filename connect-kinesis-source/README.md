# AWS Kinesis Source connector

## Objective

Quickly test [Kinesis Connector](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

## Kinesis Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` is set, see `docker-compose.yml`file for connect:

```
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:/root/.aws/credentials:ro
```

Also this example assumes that you have a default region `region=us-east-1`in your `~/.aws/credentials`:

Example:

```
$ cat ~/.aws/credentials
[default]
aws_access_key_id=XXXX
aws_secret_access_key=YYYY
region=us-east-1
output=json
```

## How to run

Simply run:

```
$ ./kinesis.sh
```

## Details

The connector is created with:

```
docker-compose exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "kinesis-source",
        "config": {
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.region": "US_EAST_1",
               "kinesis.stream": "my_kinesis_stream",
               "confluent.license": "",
               "name": "kinesis-source",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .
```


N.B: Control Center is reachable at [http://localhost:9021](http://localhost:9021])
