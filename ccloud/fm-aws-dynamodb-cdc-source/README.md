# Fully Managed AWS DynamoDB CDC source connector

## Objective

Quickly test the [Fully Managed AWS DynamoDB CDC Source](https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamodb-cdc-source.html) connector.

The table is first populated with the [Fully Managed AWS DynamoDB Sink](https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamo-db-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The Confluent Cloud cluster is expected on AWS in `AWS_REGION`.

## How to run

```bash
playground run -f fully-managed-dynamodb-cdc-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-dynamodb-cdc-source.sh` | DynamoDB Sink connector populating a table, then DynamoDB CDC Source connector reading it |

## What the script does

1. Recreates DynamoDB table `pg<USER>fmdynamocdc<TAG_BASE>` (keys `first_name` / `last_name`) and enables DynamoDB Streams (`NEW_AND_OLD_IMAGES`).
2. Bootstraps the Confluent Cloud environment and recreates topics `dynamo_cdc_input` and `<table name>`.
3. Produces 10 Avro records to `dynamo_cdc_input` with `playground topic produce`.
4. Creates the fully managed DynamoDB Sink connector `DynamoDbSink_<USER>`, waits for the lag to be 0 and verifies the data with `aws dynamodb scan`.
5. Creates the fully managed DynamoDB CDC Source connector `DynamoDbCdcSource_<USER>` (Avro output) on the table.
6. Verifies that topic `<table name>` contains 10 records (snapshot) with `playground topic consume`.
7. Asks for confirmation before deleting the connectors, then (on exit) before deleting the table.
