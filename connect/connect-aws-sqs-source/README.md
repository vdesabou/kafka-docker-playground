# AWS SQS Source connector

## Objective

Quickly test the [SQS Source](https://docs.confluent.io/kafka-connectors/sqs/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- With CP 8.0+, connector version 2.0.0 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `sqs-source-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `sqs-source-assuming-iam-role-with-custom-aws-credential-provider.sh` | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `sqs-source-assuming-iam-role-with-custom-aws-credential-provider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `sqs-source-assuming-iam-role-with-custom-aws-credential-provider.sh` | Secret key of the account allowed to assume the role |

## How to run

```bash
playground run -f sqs-source.sh
```

| Script | Description |
| --- | --- |
| `sqs-source.sh` | Static credentials (`aws.access.key.id` / `aws.secret.key.id`), also checks that consumed messages are deleted from the queue |
| `sqs-source-proxy.sh` | Same, going through an nginx forward proxy (`sqs.proxy.url=http://nginx-proxy:8888`) |
| `sqs-source-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |
| `sqs-source-assuming-iam-role-with-custom-aws-credential-provider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider` or `awscredentialsprovider-v2` for connector 2.x). ⚠️ The custom code is only an example and is not supported |

## What the script does

1. Deletes any previous queue with the same name (waiting 65 seconds if needed, as required by SQS), then creates the SQS queue `pg<user>sqs<version>` in `AWS_REGION`.
2. Sends 2 messages to the queue with `aws sqs send-message-batch` (`send-message-batch.json`).
3. Creates the SQS source connector (`io.confluent.connect.sqs.source.SqsSourceConnector`) writing to topic `test-sqs-source`.
4. Verifies the 2 messages are received in `test-sqs-source` with `playground topic consume`.
5. (`sqs-source.sh` only) Asserts the queue is empty (no visible or in-flight message), i.e. messages were deleted through the `commitRecord` API.
6. On exit, asks for confirmation and then deletes the queue.

Example of record received:

```json
{
  "ApproximateFirstReceiveTimestamp": 1569859344138,
  "ApproximateReceiveCount": 1,
  "SenderId": "AIDA6PUJEN7W4EMZQTVNV",
  "SentTimestamp": 1569858932274,
  "MessageDeduplicationId": null,
  "MessageGroupId": null,
  "SequenceNumber": null,
  "Body": "Fuel report for account 0001 on 2015-09-16 at 02:07:31 PM."
}
```

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends `benchmark message <i>` messages to the queue of the connector (`sqs.url`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), with `boto3` in a small `playground-benchmark-python` image built the first time ([`tools/benchmark-python/benchmark_producer.py`](../../tools/benchmark-python/benchmark_producer.py)), with the AWS credentials of the playground (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, or `~/.aws`). A paused connector does not receive the messages, so they wait in the queue and a drain measures the connector.

> [!IMPORTANT]
> The script deletes the queue on exit, after a `Continue (y/n)?` prompt: answer `n` to keep it for the benchmark. Running the example again deletes and recreates it.

```bash
# drain of 50000 messages, sent with send_message_batch (10 messages) from 16 threads
playground connector benchmark --nb-records 50000

# one send_message per message
playground connector benchmark --nb-records 5000 --shape small-txn

# throughput during 2 minutes while batches of 5000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 5000
```

A task receives at most 10 messages per request (`sqs.messages.max`, the SQS maximum) and deletes each message when Kafka acknowledges it: the throughput depends mostly on the latency to the region of the queue, raise `tasks.max` to receive in parallel. FIFO queues (`.fifo`) get a message group and a deduplication id.
