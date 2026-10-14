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
