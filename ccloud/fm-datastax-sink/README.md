# Fully Managed DataStax Sink connector

## Objective

Quickly test the [Fully Managed DataStax Sink](https://docs.confluent.io/cloud/current/connectors/cc-datastax-sink.html) connector with a self-hosted Apache Cassandra running in Docker.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose Cassandra port 9042 to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-datastax-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-datastax-sink.sh` | Avro records written to a self-hosted Apache Cassandra table (`deployment.type` `Apache Cassandra or DSE`) |

## What the script does

1. Starts an Apache Cassandra 4.1 container with username/password authentication (`cassandra`/`cassandra`) and ngrok locally, and gets the local datacenter name.
2. Creates keyspace `ks` and table `ks.orders` (the connector does not create keyspaces or tables).
3. Produces 10 Avro records to topic `orders` with `playground topic produce`.
4. Creates the fully managed `DataStaxSink` connector with `mapping.map` `{"orders.ks.orders":"id=value.id, product=value.product, quantity=value.quantity, price=value.price"}`.
5. Verifies that table `ks.orders` contains 10 rows.
6. Deletes the connector at the end of the run.

## Using DataStax Astra

To use DataStax Astra instead, set `deployment.type` to `DataStax Astra`, `cloud.secureConnectBundle` to the base64-encoded secure connect bundle (prefixed with `data:application/octet-stream;base64,`), `auth.username` to `token` and `auth.password` to your Astra application token.
