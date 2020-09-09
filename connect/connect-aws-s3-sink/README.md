# S3 Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-s3-sink/asciinema.gif?raw=true)

## Objective

Quickly test [S3 Sink](https://docs.confluent.io/current/connect/kafka-connect-s3/index.html#kconnect-long-amazon-s3-sink-connector) connector.



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
$ ./s3-sink.sh <AWS_BUCKET_NAME>
```

Note: you can also export these values as environment variable

## Details of what the script is doing

Creating bucket name <$AWS_BUCKET_NAME>

```bash
$ aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region us-east-1
```

The connector is created with:

```
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "s3_topic",
               "s3.region": "us-east-1",
               "s3.bucket.name": "$AWS_BUCKET_NAME",
               "s3.part.size": 52428801,
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .
```

Messages are sent to `s3_topic` topic using:

```
s$ eq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

After a few seconds, S3 should contain files in bucket:

```
$ aws s3api list-objects --bucket "$AWS_BUCKET_NAME"
```

Results:

```json
{
    "Contents": [
        {
            "Key": "topics/s3_topic/partition=0/s3_topic+0+0000000000.avro",
            "LastModified": "2020-09-09T10:00:02.000Z",
            "ETag": "\"e3df080e778bf44ddef575a8b9157f7f-1\"",
            "Size": 213,
            "StorageClass": "STANDARD",
            "Owner": {
                "DisplayName": "aws-confluent-cops-root",
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/partition=0/s3_topic+0+0000000003.avro",
            "LastModified": "2020-09-09T10:00:03.000Z",
            "ETag": "\"5d5d23e9b245019ceeacb9e579fe1091-1\"",
            "Size": 213,
            "StorageClass": "STANDARD",
            "Owner": {
                "DisplayName": "aws-confluent-cops-root",
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/partition=0/s3_topic+0+0000000006.avro",
            "LastModified": "2020-09-09T10:00:04.000Z",
            "ETag": "\"3dceb80cbe9e6eb01b3a63395ef8c18a-1\"",
            "Size": 213,
            "StorageClass": "STANDARD",
            "Owner": {
                "DisplayName": "aws-confluent-cops-root",
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        }
    ]
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
