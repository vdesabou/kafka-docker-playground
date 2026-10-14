# Fully Managed MongoDB Sink connector

## Objective

Quickly test the [Fully Managed MongoDB Sink](https://docs.confluent.io/cloud/current/connectors/cc-mongo-db-sink.html) connector with `mongodb.instance.type=MONGODB_SELF_MANAGED`.

A local MongoDB (`mongo:7.0`) is exposed to Confluent Cloud with Ngrok.

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
playground run -f fully-managed-mongodb-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mongodb-sink.sh` | Sinks Avro records to a self-managed MongoDB (collection `inventory.customers`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `mongodb.orders`.
2. Starts MongoDB, mongo-express and Ngrok, initializes the replica set and creates user `myuser`.
3. Produces 2 Avro records to `mongodb.orders`.
4. Creates the `MongoDbAtlasSink` fully managed connector with `mongodb.instance.type` `MONGODB_SELF_MANAGED`, pointing to the Ngrok address.
5. Queries `inventory.customers` with `mongosh` and checks that the `foo` record is present.
6. Asks before deleting the connector.
