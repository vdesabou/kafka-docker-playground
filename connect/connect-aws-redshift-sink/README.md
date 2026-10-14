# AWS Redshift Sink connector

## Objective

Quickly test the [AWS Redshift Sink](https://docs.confluent.io/kafka-connectors/aws-redshift/current/overview.html) connector.

## Prerequisites

- An [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws), see also [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials). The credentials must be allowed to create Redshift clusters and EC2 security groups.
- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- With CP 8.0+, connector version 1.2.0 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).
- `redshift-sink-with-assuming-iam-role.sh` only: file `$HOME/.aws/credentials-with-assuming-iam-role`, an AWS credentials file configured to assume the IAM role, mounted as `~/.aws/credentials` in the Connect container (with your `~/.aws/config`).

> [!WARNING]
> The script creates a publicly accessible single-node `ra3.large` Redshift cluster and a security group allowing ingress from `0.0.0.0/0` on port `5439`. Creating the cluster takes several minutes.

## How to run

```bash
playground run -f redshift-sink.sh
```

| Script | Description |
| --- | --- |
| `redshift-sink.sh` | Connector configured with `aws.access.key.id` / `aws.secret.key.id`; stale clusters of previous runs are reaped first |
| `redshift-sink-with-assuming-iam-role.sh` | Default credentials provider chain, with an AWS credentials file that assumes an IAM role mounted in the Connect container (not supported with `cfk`) |

## What the script does

1. Generates a random master password, stored in the `data` file and referenced by the connector with `${file:/data:password}`.
2. Creates the Redshift cluster, waits until it is `available`, then creates a security group opening port `5439` and attaches it to the cluster.
3. Produces 2 Avro records to topic `orders` with `playground topic produce`.
4. Creates the AWS Redshift sink connector (`io.confluent.connect.aws.redshift.RedshiftSinkConnector`) with `auto.create=true` and `pk.mode=kafka`.
5. Queries the `orders` table with `psql` (in a `postgres` container) and verifies the data is there.
6. On exit, asks for confirmation and then deletes the Redshift cluster and the security group.

Example of results:

```
 __connect_topic |             product             | quantity | __connect_partition | __connect_offset | price | id
-----------------+---------------------------------+----------+---------------------+------------------+-------+-----
 orders          | foo                             |      100 |                   0 |                0 |    50 | 999
(1 rows)
```
