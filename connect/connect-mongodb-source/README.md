# MongoDB source connector

## Objective

Quickly test the [MongoDB Kafka Source](https://www.mongodb.com/docs/kafka-connector/current/) connector.

## How to run

```bash
playground run -f mongo-source.sh
```

| Script | Description |
| --- | --- |
| `mongo-source.sh` | Basic example, with `output.format.value=schema` and `output.schema.infer.value=true` |
| `mongo-source-ssl.sh` | Same, with TLS encryption between the connector and MongoDB (self-signed certificate, `connection.ssl.truststore`), default output format |

With `mongo-source.sh`, the mongo-express UI is available at [http://localhost:18081/](http://localhost:18081/).

## What the script does

1. Starts the environment with a MongoDB container (`ssl` variant: first generates a self-signed certificate for `CN=mongodb` and a JKS truststore in `ssl/`).
2. Initializes the MongoDB replica set (host `mongodb:27017` is important here) and creates user `myuser` with role `dbOwner`.
3. Creates the MongoDB source connector `mongodb-source` (database `inventory`, collection `customers`, `topic.prefix=mongo`).
4. Inserts a document in collection `inventory.customers` with `mongosh`.
5. Verifies that topic `mongo.inventory.customers` receives the change event with `playground topic consume`.
