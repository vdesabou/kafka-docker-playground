# Fully Managed JDBC PostgreSQL Source connector

## Objective

Quickly test the [Fully Managed PostgreSQL Source](https://docs.confluent.io/cloud/current/connectors/cc-postgresql-source.html) connector.

A local PostgreSQL (`postgres:15`) is exposed to Confluent Cloud with Ngrok.

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
playground run -f fully-managed-jdbc-postgres-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-jdbc-postgres-source.sh` | Plain connection |
| `fully-managed-jdbc-postgres-source-ssl.sh` | SSL (self-signed CA and server certificate, `ssl.mode` verify-ca) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `postgres-customers`.
2. For the SSL variant, generates a CA and a PostgreSQL server certificate.
3. Starts PostgreSQL and Ngrok, creates table `CUSTOMERS` (with an update trigger on `update_ts`) and inserts rows.
4. Creates the `PostgresSource` fully managed connector (`timestamp+incrementing` mode, `topic.prefix` `postgres-`).
5. Verifies that 5 records are in `postgres-customers` (`playground topic consume`).
6. Asks before deleting the connector.
