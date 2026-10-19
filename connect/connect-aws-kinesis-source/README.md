# AWS Kinesis Source connector

## Objective

Quickly test the [Kinesis Source](https://docs.confluent.io/kafka-connectors/kinesis/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/kinesis/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Kinesis stream is created in `AWS_REGION`, which is also used as `kinesis.region`.
- Version guards (the scripts exit with code `111` otherwise): connector 1.3.15+ requires CP 6.0+, and with CP 8.0+ connector version 1.3.0 or later is required when `--connector-tag` is set.

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `kinesis-source-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `kinesis-source-assuming-iam-role-with-custom-awscredentialsprovider.sh` | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `kinesis-source-assuming-iam-role-with-custom-awscredentialsprovider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `kinesis-source-assuming-iam-role-with-custom-awscredentialsprovider.sh` | Secret key of the account allowed to assume the role |

## How to run

```bash
playground run -f kinesis-source.sh
```

| Script | Description |
| --- | --- |
| `kinesis-source.sh` | Static credentials (`aws.access.key.id` / `aws.secret.key.id`) |
| `kinesis-source-proxy.sh` | Same, going through an nginx forward proxy (`kinesis.proxy.url=http://nginx-proxy:8888`) |
| `kinesis-source-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |
| `kinesis-source-assuming-iam-role-with-custom-awscredentialsprovider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider` or `awscredentialsprovider-v2` for connector 2.x). ⚠️ The custom code is only an example and is not supported |

## What the script does

1. Deletes any previous stream, then creates a Kinesis stream `pg<user><version>` with 1 shard in `AWS_REGION` and waits 60 seconds for it to be ready.
2. Puts one record (partition key `123`, data `test-message-1`) into the stream with `aws kinesis put-record`.
3. Creates topic `kinesis-topic` and the Kinesis source connector (`io.confluent.connect.kinesis.KinesisSourceConnector`).
4. Verifies the record is received in `kinesis-topic` with `playground topic consume`.
5. On exit, asks for confirmation and then deletes the Kinesis stream.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) puts `benchmark message <i>` records in the stream of the connector (`kinesis.stream`, `kinesis.region`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), with `put_records` (500 records per request, the throttled records are sent again) and `boto3` in a small `playground-benchmark-python` image built the first time ([`tools/benchmark-python/benchmark_producer.py`](../../tools/benchmark-python/benchmark_producer.py)), with the AWS credentials of the playground. The records stay in the stream while the connector is paused, so a drain measures the connector.

> [!IMPORTANT]
> The script deletes the stream on exit, after a `Continue (y/n)?` prompt: answer `n` to keep it for the benchmark. Running the example again deletes and recreates it.

```bash
# drain of 50000 records
playground connector benchmark --nb-records 50000

# throughput during 2 minutes while batches of 5000 records are put
playground connector benchmark --mode steady --duration 2m --nb-records 5000
```

A shard takes 1000 records/s: the stream of the example has one shard, so loading 50000 records takes about 50 seconds, and the connector reads them much faster (a drain of a small backlog is a lower bound, the summary says so).
