# Fully Managed AWS Redshift Sink connector

## Objective

Quickly test the [Fully Managed AWS Redshift Sink](https://docs.confluent.io/cloud/current/connectors/cc-amazon-redshift-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials).

AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.

## How to run

```bash
playground run -f fully-managed-redshift-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-redshift-sink.sh` | AWS Redshift Sink connector with Avro input, creating an AWS Redshift cluster |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `redshiftorders`.
2. Deletes any previous Redshift cluster `pg<USER>fmredshift<TAG_BASE>` and its security group, then creates a single-node publicly accessible Redshift cluster with a generated password.
3. Creates security group `sg<cluster name>` allowing ingress on port 5439 from `0.0.0.0/0` and attaches it to the cluster.
4. Produces 2 Avro records to `redshiftorders` with `playground topic produce`.
5. Creates the fully managed connector `RedshiftSink_<USER>` (`auto.create=true`, `pk.mode=kafka`) and waits for it to be running.
6. Verifies with `psql` that table `redshiftorders` contains the records.
7. Asks for confirmation before deleting the connector, then (on exit) before deleting the Redshift cluster and the security group.
