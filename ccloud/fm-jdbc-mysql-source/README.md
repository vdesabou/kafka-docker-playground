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

1. Bootstraps the Confluent Cloud environment and recreates topic `mysql-CUSTOMERS`.
2. Starts MySQL and Ngrok; the SSL variant copies the MySQL certificates and builds a JKS truststore and keystore.
3. Creates table `CUSTOMERS` in database `mydb` and inserts 2 rows.
4. Creates the `MySqlSource` fully managed connector (timestamp column `update_ts`, incrementing column `id`, `topic.prefix` `mysql-`).
5. Verifies that 2 records are in `mysql-CUSTOMERS` (`playground topic consume`).
6. Asks before deleting the connector.

With `--enable-sql-datagen` (`playground run -f fully-managed-mysql-source.sh --enable-sql-datagen`), once the example succeeded, `playground run` injects rows in the `CUSTOMERS` table with [`benchmark-load.bash`](benchmark-load.bash) (the same load as `playground connector benchmark`) for 10 minutes: one row per transaction, from 5 parallel sessions. `SQL_DATAGEN_DURATION` (minutes, default `10`) and `SQL_DATAGEN_SESSIONS` (default `5`) change the duration and the number of sessions.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the same load as the self-managed example [`connect-jdbc-mysql-source`](../../connect/connect-jdbc-mysql-source/README.md): it loads rows in the `CUSTOMERS` table for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to capture 100k rows inserted in one transaction
playground connector benchmark --nb-records 100000 --shape bulk

# 10k transactions of one row
playground connector benchmark --nb-records 10000 --shape small-txn
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
