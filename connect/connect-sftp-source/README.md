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
