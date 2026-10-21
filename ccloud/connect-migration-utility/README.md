# Kafka Connector Migration Utility

## Objective

Quickly test the [Kafka Connector Migration Utility](https://github.com/confluentinc/connect-migration-utility/), which migrates self-managed connectors to fully managed connectors in Confluent Cloud.

The example migrates a self-managed AWS CloudWatch Metrics Sink connector, running on a local Connect worker connected to Confluent Cloud, to the fully managed `CloudWatchMetricsSink` connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.

With CP 8.x, the AWS CloudWatch Metrics connector version must be at least 2.0.4 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f cloudwatch-metrics-sink.sh
```

| Script | Description |
| --- | --- |
| `cloudwatch-metrics-sink.sh` | Migrate a self-managed AWS CloudWatch Metrics Sink connector to fully managed |

The script always uses the `ccloud` environment, whatever the value of `PLAYGROUND_ENVIRONMENT`. It asks for confirmation before deleting the fully managed connector at the end.

## What the script does

1. Starts the `ccloud` environment (local Connect worker connected to Confluent Cloud).
2. Produces one Avro metric record to `cloudwatch-metrics-topic` with `playground topic produce`.
3. Creates the self-managed AWS CloudWatch Metrics Sink connector `OnPremCloudWatchMetricsSink_<USER>` and verifies with `aws cloudwatch list-metrics` that the metric `test_meter_fifteenMinuteRate` exists in namespace `service-namespace`.
4. Runs `playground connector connect-migration-utility discovery` to generate the fully managed connector configuration.
5. Runs `playground connector connect-migration-utility migrate --migration-mode create_latest_offset` with the AWS credentials passed as `--sensitive-property`, which creates the fully managed connector. Outside CI, `migrate` opens the generated configuration in your editor and offers to open the connector in the browser; add `--no-open` to skip both.
6. Produces one more record and checks the consumer lag with `playground connector show-lag`.
7. Deletes the connector after confirmation.
