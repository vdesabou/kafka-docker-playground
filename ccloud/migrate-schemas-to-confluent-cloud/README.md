# Migrate Schemas to Confluent Cloud

## Objective

Quickly test [Migrate Schemas to Confluent Cloud](https://docs.confluent.io/platform/current/schema-registry/installation/migrate.html), which uses the Replicator Schema Registry migration feature (available since CP 5.2.0).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

> [!WARNING]
> The destination (Confluent Cloud) Schema Registry must not contain any subject: it is switched to `IMPORT` mode during the test. The script pauses (`check_if_continue`) after listing the destination subjects so that you can verify it.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Migrate schemas from a local Schema Registry to Confluent Cloud Schema Registry with Replicator executable |

## What the script does

1. Starts the `ccloud` environment (local Schema Registry and Control Center) and fills the Replicator executable properties files with the Confluent Cloud bootstrap servers, API key and Schema Registry credentials.
2. Deletes the `executable-products-value` subject on the destination Schema Registry, lists the remaining subjects and asks for confirmation.
3. Sets the destination Schema Registry to `IMPORT` mode and (re)creates the `executable-products` topic in Confluent Cloud.
4. Produces 3 Avro messages to `executable-products` on the on-premise broker (`kafka-avro-console-producer` in the `connect` container), which registers `executable-products-value` in the local Schema Registry.
5. Starts the Replicator executable container, which replicates the `_schemas` topic to Confluent Cloud.
6. Lists the subjects of the destination Schema Registry to verify the schema was migrated.
7. Sets the source Schema Registry to `READONLY` mode and the destination Schema Registry back to `READWRITE` mode.
