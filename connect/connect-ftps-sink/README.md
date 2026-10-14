# FTPS Sink connector

## Objective

Quickly test the [FTPS Sink](https://docs.confluent.io/current/connect/kafka-connect-ftps/sink/index.html#ftps-sink-connector-for-cp) connector.

## Prerequisites

This is a preview connector, not supported with CP 8.0 and later: the script exits with code 111 when CP 8.x is used (use `--tag 7.9.x` or earlier).

## How to run

```bash
playground run -f ftps-sink.sh --tag 7.9.0
```

| Script | Description |
| --- | --- |
| `ftps-sink.sh` | Sink Avro records to a vsftpd FTPS server (explicit mode, port 220), one Avro file per record |

## What the script does

1. Generates the keystore/truststore with `playground tools certs-create` and the vsftpd certificate with `openssl`.
2. Creates the `ftps-sink` connector (`AvroFormat`, `flush.size=1`) connecting to `ftps-server` as user `bob`.
3. Produces 10 Avro records to topic `test_ftps_sink` with `playground topic produce`.
4. Lists `/home/vsftpd/bob/test_ftps_sink/partition=0/` on the FTPS server.
5. Copies the first file locally with `playground container cp` and displays it with `playground tools read-avro-file`.

Expected result:

```json
{"f1":"value1"}
```
