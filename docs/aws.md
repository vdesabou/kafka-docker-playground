# ☁️ AWS examples: set up the credentials

The AWS examples run against a **real AWS account**:

- self-managed: `connect/connect-aws-*` (S3, Kinesis, SQS, DynamoDB, Lambda, CloudWatch Logs and Metrics, Redshift)
  and `connect/connect-jdbc-aws-*` (Redshift, Athena);
- fully managed: `ccloud/fm-aws-*`.

Every example creates its own resources (bucket `pgbucket<user>`, stream, queue, table, function…) and deletes them.
What they need is **access keys** allowed to do it and a **region**; the assume-role variants also need an **IAM
role** and the keys of a second account that assumes it.

`playground account aws setup` validates and stores the keys and the region, and optionally creates that IAM role.
`playground account aws check` tells you, in a few seconds, whether everything still works, service by service.

?> **TL;DR**: create an access key for your IAM user, `aws configure` (or pass `--profile`), run
`playground account aws setup --region <region>`, run an example.

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| The **access key of an IAM user** (not temporary credentials) | the examples and the connectors use it; fully managed connectors refuse temporary credentials | IAM → Users → your user → Security credentials → Create access key |
| Permissions on the services you run | each example creates and deletes its resources | see [Which example needs what](/aws?id=🗺️-which-example-needs-what) |
| A **region** | the examples create their resources there; the fully managed ones also their Confluent Cloud cluster | one Confluent Cloud supports (e.g. `eu-west-3`, `us-east-1`) |
| The `aws` CLI, or Docker | `setup` and `check` run it (else the `amazon/aws-cli` image the examples use) | optional |

## 🚀 Step by step

### 1. Run `playground account aws setup`

```bash
playground account aws setup --region eu-west-3                 # keys of the environment, else ~/.aws/credentials
playground account aws setup --profile my-sandbox --region eu-west-3
```

```text
🔑 keys AKIA6PUJ… from first key pair of ~/.aws/credentials, region eu-west-3
✅ keys work: arn:aws:iam::123456789012:user/you (account 123456789012)
💾 stored AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION
🩺 what these credentials can do:
…
🎉 the AWS credentials are ready for the AWS examples
```

Temporary credentials (a session token, an `ASIA…` key, an SSO profile) are refused: the fully managed connectors
can't use them, and they expire.

### 2. The assume-role variants (optional)

The `*assuming-iam-role*` scripts of the S3, DynamoDB, Kinesis, SQS, Lambda, CloudWatch and Redshift examples have
the connector assume an IAM role with the keys of a **second account** and the external id `123`. `--assume-role`
creates that role in the account of your keys:

```bash
playground account aws setup --assume-role --assume-role-profile my-second-account --dry-run   # print the policies
playground account aws setup --assume-role --assume-role-profile my-second-account
```

| Created | What for |
| --- | --- |
| Role `pg-assume-role-<user>`, trust policy: the principal of the second account, condition `sts:ExternalId = 123` | what the connector assumes (`AWS_STS_ROLE_ARN`) |
| Inline policy `pg-examples`: S3 on `pgbucket*`, Kinesis, SQS, DynamoDB, Lambda invoke, CloudWatch Logs and Metrics, Redshift describe | what the variants do with the role |
| Stored `AWS_STS_ROLE_ARN`, `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` | read by the variants |

When the second account is another AWS account, its user also needs a policy allowing `sts:AssumeRole` on the role:
`setup` says so.

The `*-with-assuming-iam-role.sh` scripts (without `-config` in their name) don't read these variables: the connector
assumes the role through its AWS SDK profile. They mount `$HOME/.aws/credentials-with-assuming-iam-role` as the
`~/.aws/credentials` of connect, a file in this format:

```ini
[default]
role_arn = arn:aws:iam::123456789012:role/pg-assume-role-you
source_profile = second-account
role_session_name = kafka-docker-playground

[second-account]
aws_access_key_id = AKIA…
aws_secret_access_key = …
```

The `aws` commands these scripts run on the host (creating the bucket, the stream…) keep using `AWS_ACCESS_KEY_ID`.

### 3. Check, then run an example

```bash
playground account aws check
playground run -f connect/connect-aws-s3-sink/s3-sink.sh
```

## 🩺 When something stops working: `playground account aws check`

`check` takes the keys exactly where the examples do (environment or secrets store, then the first key pair of
`~/.aws/credentials`), then checks the region, each service, the bucket name of your examples, and the assume-role
setup:

```text
🔑 keys AKIA6PUJ… from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (secrets store)
✅ keys work: arn:aws:iam::123456789012:user/you (account 123456789012)
✅ Region eu-west-3
✅ S3
✅ Kinesis
✅ SQS
✅ DynamoDB
✅ Lambda
✅ IAM roles
✅ CloudWatch Logs
✅ CloudWatch Metrics
✅ Redshift
✅ Athena
✅ Bucket pgbucketyou exists in eu-west-3
✅ Assume role arn:aws:iam::123456789012:role/pg-assume-role-you with the second account keys and external id 123 (like the assume-role variants)

🎉 the AWS credentials are ready for the AWS examples
```

| `check` says | Likely cause |
| --- | --- |
| `InvalidClientTokenId` | the access key id is unknown or deleted (or a session token is missing for an `ASIA…` key) |
| `SignatureDoesNotMatch` | wrong secret access key, or a stray space / CR in it |
| `ExpiredToken` | temporary credentials expired |
| `<Service>: AccessDenied…` | the IAM user lacks a permission on that service: the line lists the examples it breaks |
| `EndpointConnectionError` | `AWS_REGION` is not a valid region |
| `temporary credentials (session token)` | fine for self-managed examples, refused for `ccloud/fm-aws-*` and custom connectors |
| `Bucket pgbucket<user> belongs to another AWS account` | bucket names are global: run the S3 examples with another `USER` |
| `Bucket … exists in <region>, not in <AWS_REGION>` | the S3 examples expect it in `AWS_REGION`: delete it or change the region |
| `Assume role …: AccessDenied` | the trust policy of the role must name the principal of the second account keys, with `sts:ExternalId` `123` |

Exit code 1 means the keys don't work.

## 🗺️ Which example needs what

| Examples | Service permissions |
| --- | --- |
| `connect-aws-s3-sink` / `-source`, `fm-aws-s3-sink` / `-source`, filepulse S3 | S3 (create, list, put, get, delete the bucket `pgbucket<user>`) |
| `connect-aws-kinesis-source`, `fm-aws-kinesis-source` | Kinesis |
| `connect-aws-sqs-source`, `fm-aws-sqs-source` | SQS |
| `connect-aws-dynamodb-sink`, `fm-aws-dynamodb-sink`, `fm-aws-dynamodb-cdc-source` | DynamoDB |
| `connect-aws-lambda-sink`, `fm-aws-lambda-sink` | Lambda, and IAM (`CreateRole`, `AttachRolePolicy`, `PassRole`, `DeleteRole`: they create the role of their function) |
| `connect-aws-cloudwatch-logs-source`, `fm-aws-cloudwatch-logs-source` | CloudWatch Logs |
| `connect-aws-cloudwatch-metrics-sink`, `fm-aws-cloudwatch-metrics-sink` | CloudWatch (`PutMetricData`) |
| `connect-aws-redshift-sink`, `connect-jdbc-aws-redshift-*`, `fm-aws-redshift-sink` | Redshift and EC2 security groups (slow, and billed while running) |
| `connect-jdbc-aws-athena-source` | Athena, Glue, S3 |
| `fm-aws-s3-sink` provider integration script | `S3_PROVIDER_INTEGRATION_ID`, created by hand ([provider integration](https://docs.confluent.io/cloud/current/connectors/provider-integration/index.html)) |
| `ccloud/fm-aws-*` | also a Confluent Cloud cluster on AWS: `playground account ccloud setup --cloud aws` |

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--profile <profile>` | take the keys (and the region) from a profile of your aws CLI |
| `--region <region>` | the region of the examples |
| `--assume-role` | also create the IAM role of the assume-role variants |
| `--assume-role-profile <profile>` | the keys of the second account; default the stored `AWS_ACCOUNT_WITH_ASSUME_ROLE_*` |
| `--dry-run` | print what would be stored and the IAM policies |
| `--no-store` | print the export commands instead of storing the values |

## 💡 Good to know

- **The examples read `~/.aws/credentials` naively**: only its first key pair, whatever `AWS_PROFILE` says, and a
  session token in that file is ignored. Storing the keys with `setup` avoids the surprise.
- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)). When `secrets.github-repo` is configured (maintainers), it also pushes them to
  the GitHub Actions secrets and variables: use `--no-store` to try other keys without changing CI.
- **Costs:** a run stopped halfway can leave a Redshift cluster, a Kinesis stream or a bucket behind:
  `playground cloud-resources aws list`, and `playground cloud-resources cleanup --resource aws --dry-run`.

## 🧠 CLI reference

[playground account aws setup](/playground%20account%20aws%20setup) · [playground account aws check](/playground%20account%20aws%20check) ·
[playground secrets set](/playground%20secrets%20set)
