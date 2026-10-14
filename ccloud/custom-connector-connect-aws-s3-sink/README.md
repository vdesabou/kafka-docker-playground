# Custom Connector S3 Sink connector

## Objective

Quickly test the [Custom Connector](https://docs.confluent.io/cloud/current/connectors/bring-your-connector/overview.html) feature of Confluent Cloud with the S3 Sink connector uploaded as a custom plugin.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. Export `AWS_REGION` explicitly to choose the region of the Confluent Cloud cluster (AWS) created by the script.

| Variable | Description |
| --- | --- |
| `S3_VERSION` | Optional. Version of `confluentinc/kafka-connect-s3` uploaded as custom plugin (default `10.5.13`), downloaded from Confluent Hub if not present |

## How to run

```bash
playground run -f custom-s3-sink.sh
```

| Script | Description |
| --- | --- |
| `custom-s3-sink.sh` | S3 Sink connector deployed as a Confluent Cloud custom connector |

## What the script does

1. Downloads `confluentinc-kafka-connect-s3-<S3_VERSION>.zip` if needed and bootstraps a Confluent Cloud environment on AWS.
2. Deletes any previous custom plugin `pg_<USER>_s3_sink`, then creates it again and uploads the zip as a plugin version with `confluent ccpm plugin create` / `confluent ccpm plugin version create` (`aws.secret.access.key` declared as sensitive).
3. Creates S3 bucket `pgbucket<USER>` if needed and empties folder `<TAG>`.
4. Produces 9 Avro records and 9 invalid (non-Avro) records to `s3-topic`.
5. Creates the custom connector `S3_SINK_CUSTOM_<USER>` (Avro format, `flush.size=3`, invalid records sent to DLQ topic `dlq`) and waits for it to be running.
6. Downloads `s3-topic+0+0000000000.avro` from the bucket and displays it with `playground tools read-avro-file`.
7. On exit, asks for confirmation before deleting the connector, the plugin version and the custom plugin.
