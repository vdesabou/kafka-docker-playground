# Fully Managed Oracle Database Source (JDBC) (Oracle 19c) Source connector

## Objective

Quickly test the [Fully Managed Oracle Database Source (JDBC)](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-source.html) connector with Oracle 19c.

A local Oracle 19c database is exposed to Confluent Cloud with Ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Ngrok auth token (can also be passed as first argument) |

### Exposing the local container over the internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over the internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

An Ngrok auth token is necessary so that the fully managed connector can reach the local Docker container. Sign up at https://dashboard.ngrok.com/signup; your auth token is available on https://dashboard.ngrok.com/get-started/your-authtoken. The Ngrok web interface is available at http://localhost:4040.

Example to allow the Confluent Static Egress IP Addresses on port 1521 in an EC2 Security Group:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1521 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1521 --cidr 13.36.88.89/32
# etc...
```

### Oracle image

Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in this folder.

The first time you run the script, it builds (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the Docker image `oracle/database:19.3.0-ee`, then a prebuilt database image. It takes about 10 minutes. Confluent employees can instead get the prebuilt image from the playground S3 bucket (AWS credentials required): please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

## How to run

```bash
playground run -f fully-managed-jdbc-oracle19-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-jdbc-oracle19-source.sh` | Plain connection |
| `fully-managed-jdbc-oracle19-source-ssl.sh` | SSL (Oracle wallet created with `orapki`, `ssl.mode` verify-ca, listener config from `ssl/`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and gets or builds the Oracle image.
2. Starts Oracle and Ngrok, waits for the database to be ready, creates user `C##MYUSER` and table `CUSTOMERS` with 2 rows.
3. For the SSL variant, creates the server wallet, a JKS truststore, and reloads the listener with the SSL configuration.
4. Creates the `OracleDatabaseSource` fully managed connector (`timestamp` mode on `UPDATE_TS`, `topic.prefix` `oracle-`).
5. Verifies that 2 records are in `oracle-CUSTOMERS` (`playground topic consume`).
6. Asks before deleting the connector.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-jdbc-oracle19-source`](../../connect/connect-jdbc-oracle19-source/README.md#benchmark): it loads rows in the `CUSTOMERS` table for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to capture 100k rows inserted in one transaction
playground connector benchmark --nb-records 100000 --shape bulk

# 10k transactions of one row
playground connector benchmark --nb-records 10000 --shape small-txn
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
