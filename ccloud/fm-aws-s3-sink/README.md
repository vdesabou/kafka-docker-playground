# Fully Managed S3 Sink connector

## Objective

Quickly test the [Fully Managed S3 Sink](https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Confluent Cloud cluster is expected on AWS in `AWS_REGION`.

| Variable | Used by | Description |
| --- | --- | --- |
| `S3_PROVIDER_INTEGRATION_ID` | `fully-managed-s3-sink-confluent-cloud-provider-integration.sh` | ID of the Confluent Cloud provider integration (AWS IAM role) allowed to access the bucket, see [provider integration](https://docs.confluent.io/cloud/current/connectors/provider-integration/index.html) |

## How to run

```bash
playground run -f fully-managed-s3-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-s3-sink.sh` | S3 Sink connector authenticating with AWS access keys |
| `fully-managed-s3-sink-confluent-cloud-provider-integration.sh` | Same, authenticating with an IAM role through a Confluent Cloud provider integration (`authentication.method=IAM Roles`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `s3-topic`.
2. Creates S3 bucket `pgbucket<USER>` in `AWS_REGION` if needed and empties folder `<TAG>`.
3. Produces 1000 Avro records to `s3-topic` with `playground topic produce`.
4. Creates the fully managed connector `S3_SINK_<USER>` (or `S3_SINK_CPI_<USER>`) with Avro output, `flush.size=1000` and `time.interval=HOURLY`, and waits for it to be running.
5. Downloads `s3-topic+0+0000000000.avro` from the bucket and checks its content with `playground tools read-avro-file`.
6. Asks for confirmation before deleting the connector.
