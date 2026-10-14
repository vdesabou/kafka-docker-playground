# Fully Managed AWS Kinesis Source connector

## Objective

Quickly test the [Fully Managed Kinesis Source](https://docs.confluent.io/cloud/current/connectors/cc-kinesis-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Confluent Cloud cluster is expected on AWS in `AWS_REGION`.

The Kinesis stream is created in `AWS_REGION`, and the connector uses the same region (`kinesis.region`). If the region does not match, the connector fails to start with `Stream does not exist`.

## How to run

```bash
playground run -f fully-managed-kinesis-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-kinesis-source.sh` | AWS Kinesis Source connector reading one stream |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `kinesis-topic`.
2. Recreates Kinesis stream `pg<USER>fm<TAG_BASE>` with 1 shard.
3. Puts one record (`test-message-1`) in the stream.
4. Creates the fully managed connector `KinesisSource_<USER>` and waits for it to be running.
5. Verifies that `kinesis-topic` contains the record with `playground topic consume`.
6. Asks for confirmation before deleting the connector, then (on exit) before deleting the stream.
