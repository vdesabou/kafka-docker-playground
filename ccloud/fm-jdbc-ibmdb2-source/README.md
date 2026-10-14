# Fully Managed JDBC IBM DB2 Source connector

## Objective

Quickly test the [Fully Managed IBM DB2 Source](https://docs.confluent.io/cloud/current/connectors/cc-ibmdb2-source.html) connector.

A local IBM DB2 (`icr.io/db2_community/db2`) is exposed to Confluent Cloud with Ngrok.

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
playground run -f fully-managed-ibmdb2-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-ibmdb2-source.sh` | Plain connection |
| `fully-managed-ibmdb2-source-ssl.sh` | SSL enabled on DB2 (port 50002, `ssl.mode` require, truststore built from the DB2 server certificate) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `pg-CUSTOMERS`.
2. Starts DB2 and Ngrok, and waits for DB2 setup to complete (up to 15 minutes); the SSL variant also configures SSL on DB2 and builds a truststore.
3. Creates table `CUSTOMERS` in database `testdb` and inserts 8 rows.
4. Creates the `IbmDb2Source` fully managed connector (`timestamp+incrementing` mode, `topic.prefix` `pg-`).
5. Inserts one more row and verifies that at least 9 records are in `pg-CUSTOMERS` (`playground topic consume`).
6. Asks before deleting the connector.
