# AWS Lambda Sink connector

## Objective

Quickly test the [AWS Lambda Sink](https://docs.confluent.io/kafka-connectors/aws-lambda/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials). The credentials must be allowed to create IAM roles and Lambda functions.
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- `zip` must be installed (used to package the Lambda function).
- With CP 8.0+, connector version 2.0.13 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `lambda-sink-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `lambda-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `lambda-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `lambda-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | Secret key of the account allowed to assume the role |

## How to run

```bash
playground run -f lambda-sink.sh
```

| Script | Description |
| --- | --- |
| `lambda-sink.sh` | Static credentials (`aws.access.key.id` / `aws.secret.access.key`) |
| `lambda-sink-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |
| `lambda-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider` or `awscredentialsprovider-v2` for connector 3.x). ⚠️ The custom code is only an example and is not supported |

## What the script does

1. Creates an IAM role for Lambda (with the `AWSLambdaBasicExecutionRole` policy, to see the logs in CloudWatch) and a Lambda function (Python runtime) from `my-add-function/add.py`, which returns the sum of fields `a` and `b` of each record.
2. Produces 10 Avro records (`a`, `b`) to topic `add-topic` with `playground topic produce`.
3. Creates the AWS Lambda sink connector (`io.confluent.connect.aws.lambda.AwsLambdaSinkConnector`) with `aws.lambda.invocation.type=sync`, reporting results to `success-responses` and errors to `error-responses`.
4. Verifies 10 results are received in `success-responses` (and checks `error-responses`) with `playground topic consume`.
5. On exit, asks for confirmation and then deletes the IAM role and the Lambda function.

Example of results in `success-responses`:

```json
"{\"timestamp\":1598334450575,\"offset\":0,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":2}}"
"{\"timestamp\":1598334450609,\"offset\":1,\"partition\":0,\"topic\":\"add-topic\",\"result\":{\"sum\":3}}"
```
