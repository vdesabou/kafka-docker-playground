# Databricks Delta Lake Sink connector


## Objective

Quickly test [Databricks Delta Lake Sink](https://docs.confluent.io/kafka-connect-databricks-delta-lake-sink/current/overview.html) connector.


## Databricks Setup

Follow all steps from [here](https://docs.confluent.io/kafka-connectors/databricks-delta-lake-sink/current/databricks-aws-setup.html#set-up-databricks-delta-lake-aws)

## How to run

Simply run:

```
$ just use <playground run> command and search for databricks-delta-lake-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <DATABRICKS_AWS_BUCKET_NAME> <DATABRICKS_AWS_BUCKET_REGION> <DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID> <DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY> <DATABRICKS_SERVER_HOSTNAME> <DATABRICKS_HTTP_PATH> .sh in this folder
```

Note: you can also export these values as environment variable

## Details of what the script is doing

Create topic pageviews:

```bash
curl -s -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
               "kafka.topic": "pageviews",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.schemas.enable": "false",
               "max.interval": 10,
               "iterations": "10",
               "tasks.max": "1",
               "quickstart": "pageviews"
          }' \
     http://localhost:8083/connectors/datagen-orders/config | jq .
```

Creating Databricks Delta Lake Sink connector:

```bash
playground connector create-or-update --connector databricks-delta-lake-sink  << EOF
{
               "connector.class": "io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkConnector",
               "topics": "pageviews",
               "s3.region": "$DATABRICKS_AWS_BUCKET_REGION",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor":1,
               "delta.lake.host.name": "$DATABRICKS_SERVER_HOSTNAME",
               "delta.lake.http.path": "$DATABRICKS_HTTP_PATH",
               "delta.lake.token": "$DATABRICKS_TOKEN",
               "delta.lake.topic2table.map": "pageviews:pageviews",
               "delta.lake.table.auto.create": "true",
               "staging.s3.access.key.id": "$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID",
               "staging.s3.secret.access.key": "$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY",
               "staging.bucket.name": "$DATABRICKS_AWS_BUCKET_NAME",
               "flush.interval.ms": "100",
               "tasks.max": "1"

          }
EOF
```


Listing staging Amazon S3 bucket:

```bash
export AWS_ACCESS_KEY_ID="$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY"
aws s3api list-objects --bucket "$DATABRICKS_AWS_BUCKET_NAME"
```

You can also verify data is present in table using UI:

![ui](screenshot1.jpg)


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
