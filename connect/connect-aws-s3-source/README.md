# S3 Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-s3-source/asciinema.gif?raw=true)

## Objective

Quickly test [S3 Source](https://docs.confluent.io/kafka-connect-s3-source/current/) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set, see `docker-compose.yml`file for connect:

```yaml
    connect:
    <snip>
    volumes:
        - $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME:$CONNECT_CONTAINER_HOME_DIR/.aws/credentials
        - $HOME/.aws/config:$CONNECT_CONTAINER_HOME_DIR/.aws/config
```


## How to run

Simply run:

For [Backup and Restore Amazon S3 Source](https://docs.confluent.io/kafka-connect-s3-source/current/backup-and-restore/overview.html#)

```bash
$ ./s3-source-backup-and-restore.sh
```

For [Generalized Amazon S3 Source](https://docs.confluent.io/kafka-connect-s3-source/current/generalized/overview.html)

```bash
$ ./s3-source-generalized.sh
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
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
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
