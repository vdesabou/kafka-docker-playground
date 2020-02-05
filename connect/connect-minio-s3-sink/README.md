# S3 Sink connector with Minio

![asciinema](asciinema.gif)

## Objective

Quickly test [S3 Sink](https://docs.confluent.io/current/connect/kafka-connect-s3/index.html#kconnect-long-amazon-s3-sink-connector) connector with [Minio](https://min.io).

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)


## How to run

Simply run:

```
$ ./minio-sink.sh
```

Minio UI is accessible at [http://127.0.0.1:9000](http://127.0.0.1:9000]) (`AKIAIOSFODNN7EXAMPLE`/`wJalrXUtnFEMI7K7MDENG8bPxRfiCYEXAMPLEKEY`)

## Details of what the script is doing

The connector is created with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "minio_topic",
               "s3.bucket.name": "mybucket",
               "s3.part.size": 5242880,
               "store.url": "http://minio:9000",
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/minio-sink/config | jq .
```

Messages are sent to `minio_topic` topic using:

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic minio_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

After a few seconds, Minio should contain files in bucket:

![Minio](Screenshot1.png)


Listing objects of bucket `mybucket` in Minio:

```bash
$ docker container restart list-buckets
$ docker container logs --tail=4 list-buckets
```

```
Added `myminio` successfully.
[2020-02-05 12:41:28 UTC]    213B topics/minio_topic/partition=0/minio_topic+0+0000000000.avro
[2020-02-05 12:41:28 UTC]    213B topics/minio_topic/partition=0/minio_topic+0+0000000003.avro
[2020-02-05 12:41:28 UTC]    213B topics/minio_topic/partition=0/minio_topic+0+0000000006.avro
```

Getting one of the avro files locally and displaying content with avro-tools:

```bash
$ docker container restart copy-files
$ docker container logs --tail=3 copy-files
$ docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/minio_topic+0+0000000000.avro
```

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```
N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
