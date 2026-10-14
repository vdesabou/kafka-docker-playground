# Fully Managed Debezium MongoDB source connector

## Objective

Quickly test the [Fully Managed MongoDB CDC Source (Debezium)](https://docs.confluent.io/cloud/current/connectors/cc-mongodb-cdc-source/cc-mongodb-cdc-source-debezium.html) connector with a local MongoDB replica set.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose the MongoDB port to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-debezium-mongodb-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-debezium-mongodb-source.sh` | Plaintext MongoDB 7.0 replica set |
| `fully-managed-debezium-mongodb-source-ssl.sh` | Same with TLS: self-signed certificate, truststore passed inline to the connector (`mongodb.ssl.truststore`) |

In the plaintext variant, the mongo-express UI is available at [http://localhost:18081/](http://localhost:18081/).

## What the script does

1. Creates topic `dbserver1.inventory.customers`. The SSL variant also generates a self-signed certificate (`ssl/mongo.pem`) and a JKS truststore.
2. Starts MongoDB and ngrok locally (`docker-compose.yml` or `docker-compose-ssl.yml`).
3. Initializes the replica set `debezium`, creates user `debezium` (role `dbOwner`) and inserts one document in `inventory.customers`.
4. Creates the fully managed `MongoDbCdcSource` connector with `mongodb.connection.string` pointing to the ngrok endpoint with `replicaSet=debezium&directConnection=true` (`topic.prefix` `dbserver1`, Avro output).
5. Verifies the record in `dbserver1.inventory.customers` with `playground topic consume`.
6. Deletes the connector at the end of the run.

## Notes

`directConnection=true` is required: the replica set member is registered as `mongodb:27017`, which is not resolvable from Confluent Cloud, so the connector must not use the topology discovered from the replica set.
