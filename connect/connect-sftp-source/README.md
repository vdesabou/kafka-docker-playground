# SFTP Source connector

## Objective

Quickly test the [SFTP Source](https://docs.confluent.io/kafka-connectors/sftp/current/source-connector/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 3.2.0 or later.
* `ssh-keygen` and `openssl` on the host for the SSH key / PEM file variants.
* `sftp-source-kerberos.sh` is not supported with the `cfk` environment.

## How to run

```bash
playground run -f sftp-source-csv.sh
```

| Script | Description |
| --- | --- |
| `sftp-source-csv.sh` | CSV file with header, schema generated (`SftpCsvSourceConnector`, `schema.generation.enabled=true`) |
| `sftp-source-csv-with-schema.sh` | CSV file with explicit `key.schema` / `value.schema` |
| `sftp-source-tsv.sh` | TSV file (`csv.separator.char=9`) |
| `sftp-source-json.sh` | JSON file without schema (`SftpSchemaLessJsonSourceConnector`) |
| `sftp-source-json-with-schema.sh` | JSON file with explicit `key.schema` / `value.schema` (`SftpJsonSourceConnector`) |
| `sftp-source-ssh-key.sh` | CSV, SSH key authentication (`tls.private.key` / `tls.public.key` with a passphrase) |
| `sftp-source-ssh-pem-file.sh` | CSV, SSH key authentication with a PEM file (`tls.pemfile`) |
| `sftp-source-kerberos.sh` | CSV, Kerberos authentication (`kerberos.keytab.path`, `kerberos.user.principal`) against an SSH server with a KDC |

## What the script does

1. Starts an SFTP server (for the SSH key variants, an RSA key pair with passphrase `mypassword` is generated first; for Kerberos, principals and keytabs are created in the KDC and copied to `connect` and `ssh-server`).
2. Creates the `upload/input`, `upload/error` and `upload/finished` folders and copies a 2-line input file in `upload/input`.
3. Creates the SFTP Source connector (`cleanup.policy=NONE`) writing to topic `sftp-testing-topic`.
4. Verifies 2 records with `playground topic consume --topic sftp-testing-topic`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) writes files of users (the same fields as the records of the examples) to the `input.path` of the connector for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark): JSON lines for `SftpSchemaLessJsonSourceConnector` and `SftpJsonSourceConnector`, CSV or TSV for `SftpCsvSourceConnector` (with `csv.separator.char` and a header line when `csv.first.row.as.header` is true). The extension is the one that `input.file.pattern` accepts (`.json`, `.csv`, `.tsv` or `.txt`). The files are copied to the server next to the input folder and then moved into it, so the connector never reads a file being written. Once one of the examples is running (kerberos included: the server is the `sftp.host` of the connector):

```bash
# drain of 1000000 records in files of 10000 records
playground connector benchmark --nb-records 1000000

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

Between two files, the task waits `empty.poll.wait.ms` (default `250`): with one record per file, the connector reads about 3 files per second, whatever the size of the files.
