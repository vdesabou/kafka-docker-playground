# AWS CloudWatch Logs Source connector

## Objective

Quickly test the [AWS CloudWatch Logs Source](https://docs.confluent.io/kafka-connectors/aws-cloudwatch-logs/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- With CP 8.0+, connector version 1.3.3 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `cloudwatch-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `cloudwatch-assuming-iam-role-with-custom-awscredentialsprovider.sh` | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `cloudwatch-assuming-iam-role-with-custom-awscredentialsprovider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `cloudwatch-assuming-iam-role-with-custom-awscredentialsprovider.sh` | Secret key of the account allowed to assume the role |

## How to run

```bash
playground run -f cloudwatch.sh
```

| Script | Description |
| --- | --- |
| `cloudwatch.sh` | Static credentials (`aws.access.key.id` / `aws.secret.access.key`) |
| `cloudwatch-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |
| `cloudwatch-assuming-iam-role-with-custom-awscredentialsprovider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider` or `awscredentialsprovider-v2` for connector 2.x). ⚠️ The custom code is only an example and is not supported |

## What the script does

1. Creates a log group and a log stream in AWS CloudWatch Logs (names derived from `$USER` and the CP version).
2. Puts 11 log events into the log stream with the `aws logs put-log-events` CLI.
3. Creates the AWS CloudWatch Logs source connector (`io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector`) using `https://logs.$AWS_REGION.amazonaws.com`.
4. Verifies the 11 events are received in topic `<log group>.<log stream>` with `playground topic consume`.
5. On exit, asks for confirmation and then deletes the connector, the log stream and the log group.
