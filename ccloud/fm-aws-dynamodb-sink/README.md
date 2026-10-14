# Fully Managed AWS DynamoDB Sink connector

## Objective

Quickly test the [Fully Managed AWS DynamoDB Sink](https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamo-db-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Confluent Cloud cluster is expected on AWS in `AWS_REGION`.

## How to run

```bash
playground run -f fully-managed-dynamodb-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-dynamodb-sink.sh` | AWS DynamoDB Sink connector with Avro input |

## What the script does

1. Recreates DynamoDB table `pg<USER>fmdynamo<TAG_BASE>` (keys `first_name` / `last_name`).
2. Bootstraps the Confluent Cloud environment and recreates the topic with the same name as the table.
3. Produces 10 Avro records with `playground topic produce`.
4. Creates the fully managed connector `DynamoDbSink_<USER>` and waits for it to be running.
5. Waits for the consumer lag to be 0 with `playground connector show-lag` and verifies the data with `aws dynamodb scan`.
6. Asks for confirmation before deleting the connector, then (on exit) before deleting the table.
