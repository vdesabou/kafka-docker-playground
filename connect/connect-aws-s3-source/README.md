# S3 Source connector

## Objective

Quickly test the [S3 Source](https://docs.confluent.io/kafka-connectors/s3-source/current/index.html) connector, in both modes:

- [Backup and Restore Amazon S3 Source](https://docs.confluent.io/kafka-connectors/s3-source/current/backup-and-restore/overview.html): reads data written by the S3 sink connector.
- [Generalized Amazon S3 Source](https://docs.confluent.io/kafka-connectors/s3-source/current/generalized/overview.html) (`mode=GENERIC`, connector 2.0.0+): reads arbitrary files.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- Version guards (the scripts exit with code `111` otherwise): connector 2.0.0+ requires CP 6.0+, and with CP 8.0+ connector version 2.6.16 or later is required when `--connector-tag` is set. `s3-source-generalized.sh` requires connector 2.0.0+, `s3-source-backup-and-restore-with-assuming-iam-role-config.sh` requires connector 2.5.1+.

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `s3-source-backup-and-restore-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `*-with-assuming-iam-role-config.sh`, `*-custom-aws-credential-provider.sh` | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `*-with-assuming-iam-role-config.sh`, `*-custom-aws-credential-provider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `*-with-assuming-iam-role-config.sh`, `*-custom-aws-credential-provider.sh` | Secret key of the account allowed to assume the role |

## How to run

```bash
playground run -f s3-source-backup-and-restore.sh
```

| Script | Description |
| --- | --- |
| `s3-source-backup-and-restore.sh` | Backup and Restore mode with static credentials (`aws.access.key.id` / `aws.secret.access.key`) |
| `s3-source-backup-and-restore-proxy.sh` | Same, with the S3 sink and source connectors going through an nginx forward proxy (`s3.proxy.url=http://nginx-proxy:8888`) |
| `s3-source-backup-and-restore-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |
| `s3-source-backup-and-restore-with-assuming-iam-role-config.sh` | Built-in `io.confluent.connect.s3.auth.AwsAssumeRoleCredentialsProvider` configured with `s3.credentials.provider.sts.role.arn` (connector 2.5.1+) |
| `s3-source-backup-and-restore-assuming-iam-role-with-custom-aws-credential-provider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider` or `awscredentialsprovider-v2` for connector 3.x). Since 2.5.1 the connector ships its own `AwsAssumeRoleCredentialsProvider`. ⚠️ The custom code is only an example and is not supported |
| `s3-source-generalized.sh` | Generalized mode reading `generalized.quickstart.json` |

## What the script does

Backup and Restore scripts:

1. Creates the bucket `pgbucket<user>` in `AWS_REGION` if required, and empties the per-run folder used as `topics.dir`.
2. Creates an S3 sink connector (`AvroFormat`, `flush.size=3`) and produces 10 Avro records to `s3-topic` with `playground topic produce`.
3. Downloads one of the Avro files and displays it with `playground tools read-avro-file`.
4. Creates the S3 source connector (`io.confluent.connect.s3.source.S3SourceConnector`) on the same `topics.dir`, with a `RegexRouter` transform adding the `copy_of_` prefix.
5. Verifies 9 records (3 complete files) are received in `copy_of_s3-topic` with `playground topic consume`.

Generalized script:

1. Creates the bucket if required and uploads `generalized.quickstart.json` to a `quickstart` folder.
2. Creates the S3 source connector with `mode=GENERIC`, `JsonFormat` and `topic.regex.list=quick-start-topic:.*`.
3. Verifies 9 records are received in `quick-start-topic` with `playground topic consume`.

Example of results for the generalized mode:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```
