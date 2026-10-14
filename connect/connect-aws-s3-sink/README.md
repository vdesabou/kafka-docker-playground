# S3 Sink connector

## Objective

Quickly test the [S3 Sink](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- Version guards (the scripts exit with code `111` otherwise): with CP 8.0+, connector version 10.6.0 or later is required when `--connector-tag` is set.

Additional inputs for the IAM role variants:

| Variable / file | Used by | Description |
| --- | --- | --- |
| `$HOME/.aws/credentials-with-assuming-iam-role` | `s3-sink-with-assuming-iam-role.sh`, `s3-sink-proxy-with-assuming-iam-role.sh` | AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`) |
| `AWS_STS_ROLE_ARN` | `s3-sink-with-assuming-iam-role-config.sh`, `s3-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` (optional for `s3-sink-irsa.sh`) | ARN of the IAM role to assume |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` | `s3-sink-with-assuming-iam-role-config.sh`, `s3-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | Access key of the account allowed to assume the role |
| `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY` | `s3-sink-with-assuming-iam-role-config.sh`, `s3-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | Secret key of the account allowed to assume the role |
| `AWS_ROLE_ARN` | `s3-sink-irsa.sh` | IAM role ARN associated with the EKS service account |

## How to run

```bash
playground run -f s3-sink.sh
```

| Script | Description |
| --- | --- |
| `s3-sink.sh` | Static credentials (`aws.access.key.id` / `aws.secret.access.key`) |
| `s3-sink-proxy.sh` | Same, going through an nginx forward proxy (`s3.proxy.url=http://nginx-proxy:8888`) |
| `s3-sink-proxy-basic-auth.sh` | Same, going through a squid forward proxy with basic authentication (`s3.proxy.user` / `s3.proxy.password`) |
| `s3-sink-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |
| `s3-sink-with-assuming-iam-role-config.sh` | Built-in `io.confluent.connect.s3.auth.AwsAssumeRoleCredentialsProvider` configured with `s3.credentials.provider.sts.role.arn`, using the assume-role account keys as `aws.access.key.id` / `aws.secret.access.key` |
| `s3-sink-assuming-iam-role-with-custom-aws-credential-provider.sh` | AssumeRole with a custom AWS credentials provider (`com.github.vdesabou.AwsAssumeRoleCredentialsProvider`, built from `awscredentialsprovider` or `awscredentialsprovider-v2` for connector 11.x). ⚠️ The custom code is only an example and is not supported |
| `s3-sink-irsa.sh` | Custom `com.github.vdesabou.AwsAssumeRoleIrsaCredentialsProvider` (built from `awscredentialsprovider-v2-irsa`) for IAM Roles for Service Accounts (IRSA) in EKS. ⚠️ Not supported; outside EKS the web identity token and `AWS_ROLE_ARN` are not injected in the Connect container |
| `s3-sink-proxy-with-assuming-iam-role.sh` | Proxy + assuming IAM role: always exits with code `111`, it does not work because of [aws/aws-sdk-java#2558](https://github.com/aws/aws-sdk-java/issues/2558) |

## What the script does

1. Creates the bucket `pgbucket<user>` in `AWS_REGION` if required, and empties the per-run folder used as `topics.dir`.
2. Creates the S3 sink connector (`io.confluent.connect.s3.S3SinkConnector`) with `AvroFormat` and `flush.size=3`.
3. Produces 10 Avro records to topic `s3-topic` with `playground topic produce`.
4. Downloads `s3-topic/partition=0/s3-topic+0+0000000000.avro` from the bucket and displays it with `playground tools read-avro-file`.
