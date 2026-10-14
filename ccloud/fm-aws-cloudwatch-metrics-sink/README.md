# Fully Managed AWS CloudWatch Metrics Sink connector

## Objective

Quickly test the [Fully Managed AWS CloudWatch Metrics Sink](https://docs.confluent.io/cloud/current/connectors/cc-amazon-cloudwatch-metrics-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Confluent Cloud cluster is expected on AWS in `AWS_REGION`.

## How to run

```bash
playground run -f fully-managed-cloudwatch-metrics-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-cloudwatch-metrics-sink.sh` | AWS CloudWatch Metrics Sink connector with Avro input |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `cloudwatch-metrics-topic` (1 partition).
2. Produces one Avro metric record (`test_meter`, type `meter`) with `playground topic produce`.
3. Creates the fully managed connector `CloudWatchMetricsSink_<USER>` (namespace `service-namespace`) and waits for it to be running.
4. Verifies with `aws cloudwatch list-metrics` that metric `test_meter_fifteenMinuteRate` exists in namespace `service-namespace`.
5. Asks for confirmation before deleting the connector.
