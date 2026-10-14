# Fully Managed JDBC MySQL Sink connector

## Objective

Quickly test the [Fully Managed MySQL Sink](https://docs.confluent.io/cloud/current/connectors/cc-mysql-sink.html) connector.

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
playground run -f fully-managed-mysql-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mysql-sink.sh` | Sinks Avro records to MySQL database `mydb` (auto-create table) |

## What the script does

1. Bootstraps the Confluent Cloud environment, deletes topic `mysqlorders` and produces 2 Avro records to it.
2. Starts MySQL and Ngrok.
3. Creates the `MySqlSink` fully managed connector (`insert.mode` INSERT, `auto.create` and `auto.evolve`).
4. Describes and queries table `mysqlorders` and checks that the `foo` record is present.
5. Asks before deleting the connector.
