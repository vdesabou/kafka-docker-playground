# Fully Managed Datagen Source connector

## Objective

Quickly test the [Fully Managed Datagen Source](https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f fully-managed-datagen-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-datagen-source.sh` | `PAGEVIEWS` quickstart, Avro output to topic `datagen_pageviews` |

## What the script does

1. Creates topic `datagen_pageviews`.
2. Creates the fully managed `DatagenSource` connector (`quickstart` `PAGEVIEWS`, Avro, one record every 10 seconds at most).
3. Verifies that at least 5 records are produced with `playground topic consume`.
4. Deletes the connector at the end of the run.
