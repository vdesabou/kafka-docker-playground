# MongoDB sink connector

## Objective

Quickly test the [MongoDB Kafka Sink](https://www.mongodb.com/docs/kafka-connector/current/) connector.

## How to run

```bash
playground run -f mongo-sink.sh
```

| Script | Description |
| --- | --- |
| `mongo-sink.sh` | Basic example |
| `mongo-sink-ssl.sh` | Same, with TLS encryption between the connector and MongoDB (self-signed certificate, `connection.ssl.truststore`) |

With `mongo-sink.sh`, the mongo-express UI is available at [http://localhost:18081/](http://localhost:18081/).

## What the script does

1. Starts the environment with a MongoDB container (`ssl` variant: first generates a self-signed certificate for `CN=mongodb` and a JKS truststore in `ssl/`).
2. Initializes the MongoDB replica set (host `mongodb:27017` is important here) and creates user `myuser` with role `dbOwner`.
3. Produces 2 Avro records to topic `orders` with `playground topic produce`.
4. Creates the MongoDB sink connector `mongodb-sink` (database `inventory`, collection `customers`).
5. Verifies with `mongosh` that the records are in collection `inventory.customers`.

Example of document:

```json
{
  "_id": ObjectId("5defb320169c4051ecbb50bf"),
  "id": 2,
  "product": "foo",
  "quantity": 2,
  "price": 0.86583304
}
```
