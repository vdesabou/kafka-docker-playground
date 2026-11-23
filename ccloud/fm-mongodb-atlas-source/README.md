# Fully Managed MongoDB Atlas Source connector

## Objective

Quickly test the [Fully Managed MongoDB Atlas Source](https://docs.confluent.io/cloud/current/connectors/cc-mongo-db-source.html) connector.

## Prerequisites

> `playground account mongodb-atlas setup` validates and stores the values below, `playground account mongodb-atlas check` tells you in a few seconds whether they still work (expired, paused, idle…), see [Accounts of the examples](https://kafka-docker-playground.io/#/accounts?id=🧾-the-saas-accounts).

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `MONGODB_ATLAS_HOST` | MongoDB Atlas host, without `mongodb+srv://` (e.g. `cluster0.xxxxx.mongodb.net`) |
| `MONGODB_ATLAS_USER` | MongoDB Atlas database user |
| `MONGODB_ATLAS_PASSWORD` | MongoDB Atlas database password |

They can also be passed as positional arguments, in this order. The Atlas cluster must accept connections from Confluent Cloud and from your machine (the script uses `mongosh` in Docker).

## How to run

```bash
playground run -f fully-managed-mongodb-atlas-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mongodb-atlas-source.sh` | Reads collection `inventory.customers` from MongoDB Atlas (`startup.mode` copy_existing, JSON output) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `mongo.inventory.customers`.
2. Drops collection `inventory.customers` in Atlas and inserts one document.
3. Creates the `MongoDbAtlasSource` fully managed connector (`topic.prefix` `mongo`).
4. Inserts a second document and verifies that 2 records are in `mongo.inventory.customers` (`playground topic consume`).
5. Asks before deleting the connector.
