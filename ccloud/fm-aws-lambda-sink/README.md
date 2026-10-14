# Fully Managed AWS Lambda Sink connector

## Objective

Quickly test the [Fully Managed AWS Lambda Sink](https://docs.confluent.io/cloud/current/connectors/cc-aws-lambda-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`. The AWS user must be allowed to create IAM roles and Lambda functions.

## How to run

```bash
playground run -f fully-managed-lambda-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-lambda-sink.sh` | AWS Lambda Sink connector invoking a Python function synchronously |

## What the script does

1. Recreates IAM role `pg<USER>fmlambdabrole<TAG_BASE>` (with the `AWSLambdaBasicExecutionRole` policy) and Lambda function `pg<USER>fmlambdafn<TAG_BASE>` from `my-add-function/add.py` (runtime `python3.12`).
2. Bootstraps the Confluent Cloud environment and recreates topic `add-topic`.
3. Produces 10 Avro records with `playground topic produce`.
4. Creates the fully managed connector `LambdaSink_<USER>` (`single` configuration mode, `sync` invocation) and waits for it to be running.
5. Verifies that the `success-<connector id>` topic contains 10 records, and displays the `error-<connector id>` topic, with `playground topic consume`.
6. Asks for confirmation before deleting the connector, then (on exit) before deleting the role and the function.
