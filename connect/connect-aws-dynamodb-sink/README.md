# AWS DynamoDB Sink connector

## Objective

Quickly test the [AWS DynamoDB Sink](https://docs.confluent.io/kafka-connectors/aws-dynamodb/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- Version guards (the scripts exit with code `111` otherwise): connector 1.3.0+ requires CP 6.0+, and with CP 8.0+ connector version 1.5.0 or later is required when `--connector-tag` is set.

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `dynamodb-sink-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `*-assuming-iam-role-config.sh`, `*-custom-aws-credential-provider.sh` | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `*-assuming-iam-role-config.sh`, `*-custom-aws-credential-provider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `*-assuming-iam-role-config.sh`, `*-custom-aws-credential-provider.sh` | Secret key of the account allowed to assume the role |

## How to run

```bash
playground run -f dynamodb-sink.sh
```

| Script | Description |
| --- | --- |
| `dynamodb-sink.sh` | Default credentials provider chain, using the AWS credentials file mounted in the Connect container (not supported with `cfk`) |
| `dynamodb-sink-proxy.sh` | Same, going through an nginx forward proxy (`aws.dynamodb.proxy.url=http://nginx-proxy:8888`, not supported with `cfk`) |
| `dynamodb-sink-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role (not supported with `cfk`) |
| `dynamodb-sink-with-assuming-iam-role-config.sh` | Built-in `io.confluent.connect.aws.dynamodb.auth.AwsAssumeRoleCredentialsProvider` configured with `aws.dynamodb.credentials.provider.sts.role.arn` (the Connect worker gets the assume-role account keys as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables) |
| `dynamodb-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider`). ⚠️ The custom code is only an example and is not supported |
| `dynamodb-sink-with-custom-basic-aws-credentials-provider.sh` | Custom `com.github.vdesabou.BasicAwsCredentialsProvider` (built from `basicawscredentialsprovider`) with access key and secret in the connector config. ⚠️ The custom code is only an example and is not supported |

## What the script does

1. Creates (or re-creates) the DynamoDB table `pg<user>dynamo<version>` with hash key `first_name` and range key `last_name`, and waits for it to be `ACTIVE`.
2. Produces 10 Avro records (`first_name`, `last_name`) to the topic named after the table with `playground topic produce`.
3. Creates the AWS DynamoDB sink connector (`io.confluent.connect.aws.dynamodb.DynamoDbSinkConnector`) using `https://dynamodb.$AWS_REGION.amazonaws.com`.
4. Waits for the connector to consume all records (`playground connector show-lag`).
5. Scans the table with `aws dynamodb scan` and verifies the records are there.
6. On exit, asks for confirmation and then deletes the table.
