# GraphDB Sink connector

## Objective

Quickly test the [kafka-sink-graphdb](https://github.com/Ontotext-AD/kafka-sink-graphdb/tree/main) connector (self-managed).

## Prerequisites

The connector zip `kafka-sink-graphdb-plugin.zip` is downloaded with `get_3rdparty_file`: this example can only be run by Confluent employees.

## How to run

```bash
playground run -f graphdb-sink.sh
```

| Script | Description |
| --- | --- |
| `graphdb-sink.sh` | GraphDB sink with no authentication, RDF payload (N-Quads) |

## What the script does

1. Starts the environment with a GraphDB container and creates the `test` repository through the GraphDB REST API.
2. Creates the `graphdb-sink` connector (`com.ontotext.kafka.GraphDBSinkConnector`) with `DirectRDFConverter`, `graphdb.update.type=ADD` and `graphdb.update.rdf.format=nq`, then restarts it (the first start can fail with a `NoSuchMethodError`, see the comment in the script).
3. Produces 10 RDF statements `<urn:a> <urn:b> <urn:c> .` to topic `test`.
4. Data is not verified automatically: open http://127.0.0.1:7200/sparql, select the `test` repository and run:

```sql
select * where { <urn:a> ?p ?o . }
```
