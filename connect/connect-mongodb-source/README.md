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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads documents in the collection of the connector (`inventory.customers`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). The documents have the shape of an existing document of the collection (same fields, integer `_id` continued), so that the schema inferred by the connector (`output.schema.infer.value`) stays compatible. Once the example is running:

```bash
# time to capture 1M documents inserted with insertMany
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k insertOne, then 1M updates of existing documents
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update
```

The connector is paused while the documents are loaded (the change stream resumes from its last position), then resumed, and the benchmark measures the time it takes to produce the records.
