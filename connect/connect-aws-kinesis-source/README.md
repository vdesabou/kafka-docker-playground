# AWS Kinesis Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-kinesis-source/asciinema.gif?raw=true)

## Objective

Quickly test [Kinesis Connector](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#quick-start) connector.

## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#aws-credentials)

This project assumes `~/.aws/credentials` is set, see `docker-compose.yml`file for connect:

```
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:/root/.aws/credentials:ro
```

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
$ ./kinesis.sh
```

## Details of what the script is doing

Create a Kinesis stream `my_kinesis_stream` in `us-east-1` region as it is default:

```
$ aws kinesis create-stream --stream-name my_kinesis_stream --shard-count 1
```

Insert records in Kinesis stream:

```
$ aws kinesis put-record --stream-name my_kinesis_stream --partition-key 123 --data test-message-1
```

The connector is created with:

```
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.region": "EU_WEST_3",
               "kinesis.stream": "my_kinesis_stream",
               "confluent.license": "",
               "name": "kinesis-source",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source/config | jq .
```

Verify we have received the data in kinesis_topic topic:

```
$ docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1
```

Delete your stream and clean up resources to avoid incurring any unintended charges:

```
aws kinesis delete-stream --stream-name my_kinesis_stream
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
