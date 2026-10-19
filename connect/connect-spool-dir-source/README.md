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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) writes files of users (the same fields as the records of the examples) to the `input.path` of the connector, in the connect container, for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark): JSON lines for `SpoolDirJsonSourceConnector`, `SpoolDirSchemaLessJsonSourceConnector` and `SpoolDirLineDelimitedSourceConnector`, CSV or TSV for `SpoolDirCsvSourceConnector` (with `csv.separator.char` and a header line when `csv.first.row.as.header` is true). The extension is the one that `input.file.pattern` accepts. The files are copied next to the input folder and then moved into it, so the connector never reads a file being written. Once one of the examples is running:

```bash
# drain of 200000 records in files of 10000 records
playground connector benchmark --nb-records 200000

# per-file overhead: 300 files of one record
playground connector benchmark --nb-records 300 --shape small-txn

# throughput during 2 minutes while files of 50000 records are written
playground connector benchmark --mode steady --duration 2m --nb-records 50000
```

| Option | Load |
| --- | --- |
| `--shape bulk` (default) | files of `BENCHMARK_FILE_RECORDS` records (default `10000`) |
| `--shape small-txn` | one record per file: the cost of listing, opening and moving each file (drain only) |
| `--mode steady` | one file of `--nb-records` records per batch |
