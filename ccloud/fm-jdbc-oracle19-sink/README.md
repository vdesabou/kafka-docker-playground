# Fully Managed JDBC Oracle 19c Sink connector

## Objective

Quickly test the [Fully Managed Oracle Database Sink](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-sink.html) connector with Oracle 19c.

A local Oracle 19c database is exposed to Confluent Cloud with Ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Ngrok auth token (can also be passed as first argument) |

### Exposing the local container over the internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over the internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

An Ngrok auth token is necessary so that the fully managed connector can reach the local Docker container. Sign up at https://dashboard.ngrok.com/signup; your auth token is available on https://dashboard.ngrok.com/get-started/your-authtoken. The Ngrok web interface is available at http://localhost:4040.

### Oracle image

Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in this folder.

The first time you run the script, it builds (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the Docker image `oracle/database:19.3.0-ee`, then a prebuilt database image. It takes about 10 minutes. Confluent employees can instead get the prebuilt image from the playground S3 bucket (AWS credentials required): please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

## How to run

```bash
playground run -f fully-managed-jdbc-oracle19-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-jdbc-oracle19-sink.sh` | Sinks Avro records to Oracle table `ORDERS` (auto-create) |

## What the script does

1. Bootstraps the Confluent Cloud environment and gets or builds the Oracle image.
2. Starts Oracle and Ngrok, waits for the database to be ready and creates user `C##MYUSER`.
3. Produces 2 Avro records to topic `ORDERS`.
4. Creates the `OracleDatabaseSink` fully managed connector (`auto.create`, `auto.evolve`, `ssl.mode` disabled).
5. Queries table `ORDERS` with `sqlplus` and checks that the `foo` record is present.
6. Asks before deleting the connector.
