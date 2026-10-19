# FTPS Source connector

## Objective

Quickly test the [FTPS Source](https://docs.confluent.io/current/connect/kafka-connect-ftps/source/index.html#ftps-source-connector-for-cp) connector.

## Prerequisites

This is a preview connector, not supported with CP 8.0 and later: the script exits with code 111 when CP 8.x is used (use `--tag 7.9.x` or earlier).

## How to run

```bash
playground run -f ftps-source.sh --tag 7.9.0
```

| Script | Description |
| --- | --- |
| `ftps-source.sh` | Read a JSON file from a vsftpd FTPS server (explicit mode, port 220) with explicit key and value schemas |

## What the script does

1. Generates the keystore/truststore with `playground tools certs-create` and the vsftpd certificate with `openssl`.
2. Creates the `input`, `error` and `finished` folders for user `bob` on the FTPS server and copies a JSON file with 2 records into `input`.
3. Creates the `ftps-source-json` connector (`schema.generation.enabled=false`, with `key.schema` and `value.schema`) writing to topic `ftps-testing-topic`.
4. Verifies topic `ftps-testing-topic` with `playground topic consume`.

Expected result:

```json
{"id":1,"first_name":{"string":"Roscoe"},"last_name":{"string":"Brentnall"},"email":{"string":"rbrentnall0@mediafire.com"},"gender":{"string":"Male"},"ip_address":{"string":"202.84.142.254"},"last_login":{"string":"2018-02-12T06:26:23Z"},"account_balance":{"bytes":"\u00026¬"},"country":{"string":"CZ"},"favorite_color":{"string":"#4eaefa"}}
```

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) writes files of JSON users (the records of the example) to the `ftps.input.path` of the connector for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), in the home of its user on the `ftps-server` container (`/home/vsftpd/<ftps.username>`). The files are copied next to the input folder and then moved into it, so the connector never reads a file being written. Once the example is running:

```bash
# drain of 100000 records in files of 10000 records
playground connector benchmark --nb-records 100000

# per-file overhead: 300 files of one record
playground connector benchmark --nb-records 300 --shape small-txn

# throughput during 2 minutes while files of 20000 records are written
playground connector benchmark --mode steady --duration 2m --nb-records 20000
```

| Option | Load |
| --- | --- |
| `--shape bulk` (default) | files of `BENCHMARK_FILE_RECORDS` records (default `10000`) |
| `--shape small-txn` | one record per file: the cost of listing, opening and moving each file (drain only) |
| `--mode steady` | one file of `--nb-records` records per batch |

The FTPS connector is a preview connector, not supported with CP 8 (the example exits with code `111`): run it with `--tag 7.9.0`. On 2026-10-19 the example failed there too, when creating the connector (`Error when trying to establish connection to the FTPS server`), so this load is only checked with `--check`. `ftps.input.file.pattern` is `.*\.json` so that the files of the load are read too.
