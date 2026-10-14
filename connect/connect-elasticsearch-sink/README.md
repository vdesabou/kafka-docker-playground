# Elasticsearch Sink connector

## Objective

Quickly test the [Elasticsearch Sink](https://docs.confluent.io/kafka-connectors/elasticsearch/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimal supported connector version is `14.1.0` (the script exits with code 111 otherwise).

The Elasticsearch version depends on the connector version:

- connector 16.0.0 and later (Elasticsearch Java API Client, supports Elasticsearch 8.x and 9.x): Elasticsearch `9.3.0`
- connector before 16.0.0 (High Level REST Client 7.17, supports Elasticsearch 7.x and 8.x): Elasticsearch `8.18.2`

| Variable | Description |
| --- | --- |
| `ELASTIC_VERSION` | Optional: Elasticsearch version to use instead of the default above |

## How to run

```bash
playground run -f elasticsearch-sink.sh
```

| Script | Description |
| --- | --- |
| `elasticsearch-sink.sh` | Elasticsearch Sink connector writing to a local Elasticsearch container |

## What the script does

1. Picks the Elasticsearch version from the connector version (also detected from `--connector-zip` / `--connector-jar` file names) and starts the environment.
2. Produces 10 Avro records to topic `test-elasticsearch-sink` with `playground topic produce`.
3. Creates the `elasticsearch-sink` connector with `key.ignore=true` and `connection.url=http://elasticsearch:9200`.
4. Queries `http://localhost:9200/test-elasticsearch-sink/_search` and checks that the records are indexed.
