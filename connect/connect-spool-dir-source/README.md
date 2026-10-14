# Spool Dir Source connector

## Objective

Quickly test the [Spool Dir Source](https://docs.confluent.io/kafka-connectors/spooldir/current/overview.html) connectors.

## Prerequisites

* With CP 8.x, connector version 2.0.0 or later.

## How to run

```bash
playground run -f csv.sh
```

| Script | Description |
| --- | --- |
| `csv.sh` | CSV file with header and explicit `key.schema` / `value.schema` (`SpoolDirCsvSourceConnector`), topic `spooldir-csv-topic` |
| `tsv.sh` | TSV file (`csv.separator.char=9`) with generated schema, topic `spooldir-tsv-topic` |
| `json.sh` | JSON file with explicit `key.schema` / `value.schema` (`SpoolDirJsonSourceConnector`), topic `spooldir-json-topic` |
| `json-schemaless.sh` | JSON file without schema (`SpoolDirSchemaLessJsonSourceConnector`), topic `spooldir-schemaless-json-topic` |
| `line-delimited.sh` | FIX encoded lines, one record per line (`SpoolDirLineDelimitedSourceConnector`), topic `fix-topic` |

## What the script does

1. Creates `/tmp/data/input`, `/tmp/data/error` and `/tmp/data/finished` in the `connect` container and downloads a sample input file into `/tmp/data/input` (from Mockaroo, or the FIX sample file of the [kafka-connect-spooldir](https://github.com/jcustenborder/kafka-connect-spooldir) test resources).
2. Creates the Spool Dir Source connector reading `/tmp/data/input` (`halt.on.error=false`).
3. Verifies at least 10 records with `playground topic consume` on the target topic.
