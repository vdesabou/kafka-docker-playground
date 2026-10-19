# Fully Managed AWS SQS Source connector

## Objective

Quickly test the [Fully Managed SQS Source](https://docs.confluent.io/cloud/current/connectors/cc-amazon-sqs-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Confluent Cloud cluster is expected on AWS in `AWS_REGION`.

## How to run

```bash
playground run -f fully-managed-sqs-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-sqs-source.sh` | AWS SQS Source connector with JSON output |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `test-sqs-source`.
2. Recreates SQS queue `pg<USER>fmsqs<TAG_BASE>` in `AWS_REGION`.
3. Sends the messages of `send-message-batch.json` with `aws sqs send-message-batch`.
4. Creates the fully managed connector `SqsSource_<USER>` and waits for it to be running.
5. Verifies that `test-sqs-source` contains 2 records with `playground topic consume`, and that the SQS queue is empty afterwards (messages deleted once committed).
6. Asks for confirmation before deleting the connector, then (on exit) before deleting the queue.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-aws-sqs-source`](../../connect/connect-aws-sqs-source/README.md#benchmark): it loads messages in the SQS queue for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
