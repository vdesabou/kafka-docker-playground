# Fully Managed MongoDB Atlas Sink connector

## Objective

Quickly test the [Fully Managed MongoDB Atlas Sink](https://docs.confluent.io/cloud/current/connectors/cc-mongo-db-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `MONGODB_ATLAS_HOST` | MongoDB Atlas host, without `mongodb+srv://` (e.g. `cluster0.xxxxx.mongodb.net`) |
| `MONGODB_ATLAS_USER` | MongoDB Atlas database user |
| `MONGODB_ATLAS_PASSWORD` | MongoDB Atlas database password |

They can also be passed as positional arguments, in this order. The Atlas cluster must accept connections from Confluent Cloud and from your machine (the script uses `mongosh` in Docker).

## How to run

```bash
playground run -f fully-managed-mongodb-atlas-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mongodb-atlas-sink.sh` | Sinks Avro records to collection `inventory.customers` in MongoDB Atlas |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `mongodborders`.
2. Drops collection `inventory.customers` in Atlas.
3. Produces 2 Avro records to `mongodborders`.
4. Creates the `MongoDbAtlasSink` fully managed connector.
5. Queries `inventory.customers` with `mongosh` and checks that the `foo` record is present.
6. Asks before deleting the connector.
