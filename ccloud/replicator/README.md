# Replicator (using Confluent Cloud)

## Objective

Quickly test [Replicator](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html) running as a connector on a local Connect worker, replicating from a local (on-premise) cluster to Confluent Cloud.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Requires CP lower than 8.0.0 (the scripts exit with code `111` otherwise).

## How to run

```bash
playground run -f connect-onprem-to-cloud.sh
```

| Script | Description |
| --- | --- |
| `connect-onprem-to-cloud.sh` | Replicates topic `products` with `io.confluent.connect.replicator.util.ByteArrayConverter` (schemas are not preserved) |
| `connect-onprem-to-cloud-avro.sh` | Replicates topic `products-avro` with `AvroConverter`: schemas are registered in Confluent Cloud Schema Registry |
| `connect-onprem-to-cloud-avro-with-sr-basic-auth.sh` | Same as the Avro example (Avro key and value), with a local Schema Registry protected by basic authentication |

The default `value.converter` (`io.confluent.connect.replicator.util.ByteArrayConverter`) does not preserve schemas. The `*avro*.sh` scripts use `io.confluent.connect.avro.AvroConverter` to preserve them, as documented in [Replicating messages with schemas](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html#replicating-messages-with-schemas).

Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021).

## What the script does

1. Starts the `ccloud` environment with a local broker, Schema Registry and Connect worker.
2. (Re)creates the destination topic in Confluent Cloud (`auto.create.topics.enable=false`).
3. Produces messages to the topic on the local cluster (10 string messages, or 3 Avro messages for the Avro variants).
4. Creates the `replicate-onprem-to-cloud` Replicator connector with Confluent Cloud as destination (`topic.auto.create=false`, `topic.config.sync=false`).
5. Verifies the messages are received in Confluent Cloud with `playground topic consume`.
