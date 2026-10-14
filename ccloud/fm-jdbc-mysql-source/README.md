# Fully Managed JDBC MySQL Source connector

## Objective

Quickly test the [Fully Managed MySQL Source](https://docs.confluent.io/cloud/current/connectors/cc-mysql-source.html) connector.

A local MySQL (`mysql:8.1`) is exposed to Confluent Cloud with Ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Ngrok auth token (can also be passed as first argument) |

### Exposing the local container over the internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over the internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

An Ngrok auth token is necessary so that the fully managed connector can reach the local Docker container. Sign up at https://dashboard.ngrok.com/signup; your auth token is available on https://dashboard.ngrok.com/get-started/your-authtoken. The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-mysql-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mysql-source.sh` | Plain connection |
| `fully-managed-mysql-source-ssl.sh` | SSL (`ssl.mode` require, truststore built from the MySQL CA, user `userssl`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `mysql-team`.
2. Starts MySQL and Ngrok; the SSL variant copies the MySQL certificates and builds a JKS truststore and keystore.
3. Creates table `team` in database `mydb` and inserts 2 rows.
4. Creates the `MySqlSource` fully managed connector (timestamp column `last_modified`, incrementing column `id`, `topic.prefix` `mysql-`).
5. Verifies that 2 records are in `mysql-team` (`playground topic consume`).
6. Asks before deleting the connector.
