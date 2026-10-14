# AWS CloudWatch Metrics Sink connector

## Objective

Quickly test the [AWS CloudWatch Metrics Sink](https://docs.confluent.io/kafka-connectors/aws-cloudwatch-metrics/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- With CP 8.0+, connector version 2.0.4 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).
- `cloudwatch-metrics-sink-with-assuming-iam-role.sh` only: file `$HOME/.aws/credentials-with-assuming-iam-role`, an AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`).

## How to run

```bash
playground run -f cloudwatch-metrics-sink.sh
```

| Script | Description |
| --- | --- |
| `cloudwatch-metrics-sink.sh` | Static credentials (`aws.access.key.id` / `aws.secret.access.key`) |
| `cloudwatch-metrics-sink-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |

## What the script does

1. Produces one Avro `meter` metric record (key `key1`) to topic `cloudwatch-metrics-topic` with `playground topic produce`.
2. Creates the AWS CloudWatch Metrics sink connector (`io.confluent.connect.aws.cloudwatch.metrics.AwsCloudWatchMetricsSinkConnector`) writing to namespace `service-namespace` on `https://monitoring.$AWS_REGION.amazonaws.com`.
3. Lists the metrics of namespace `service-namespace` with `aws cloudwatch list-metrics` and verifies `test_meter_fifteenMinuteRate` is present.

Expected metrics: `test_meter_count`, `test_meter_oneMinuteRate`, `test_meter_fiveMinuteRate`, `test_meter_fifteenMinuteRate` and `test_meter_meanRate`, each with dimensions `dimensions1=InstanceID` and `dimensions2=i-aaba32d4`.
