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
