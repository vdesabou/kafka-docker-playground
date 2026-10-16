# Debezium PostgreSQL source connector

## Objective

Quickly test the [Debezium PostgreSQL](https://docs.confluent.io/kafka-connectors/debezium-postgres-source/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimal supported connector version is `2.5.0` (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f debezium-postgres-source.sh
```

| Script | Description |
| --- | --- |
| `debezium-postgres-source.sh` | Basic example, Avro converters and a `RegexRouter` SMT adding a `-raw` suffix to topic names |
| `debezium-postgres-source-ssl.sh` | PostgreSQL with SSL encryption (`database.sslmode=verify-full`) |
| `debezium-postgres-source-mtls.sh` | PostgreSQL with SSL encryption and mutual TLS authentication (no password) |
| `debezium-postgres-source-partitioned-tables.sh` | Partitioned `CUSTOMERS` table captured through a `pgoutput` publication created with `publish_via_partition_root = true` |
| `debezium-postgres-source-incremental-snapshot.sh` | Ad hoc incremental snapshot of a newly added table, triggered through the signaling table `public.debezium_signal` |
| `debezium-postgres-source-incremental-snapshot-kafka-signal.sh` | Same, triggered through the Kafka signal topic `dbz-signals` |

## What the script does

`debezium-postgres-source.sh` (the SSL, mTLS and partitioned variants follow the same steps):

1. Starts the environment with a PostgreSQL container (`debezium/postgres:15-alpine`).
2. Creates table `CUSTOMERS`, inserts sample rows and adds one more row.
3. Creates the `debezium-postgres-source` connector (`topic.prefix` `asgard`).
4. Verifies that topic `asgard.public.customers-raw` contains the records with `playground topic consume`.

The incremental snapshot variants:

1. Create tables `customers` and `customers2` and the signaling table `debezium_signal`.
2. Create the connector with `table.include.list=public.customers` and verify `asgard.public.customers`.
3. Update the connector to also include `public.customers2`, insert a row: only this new row shows up in `asgard.public.customers2`.
4. Send an `execute-snapshot` signal (insert into `debezium_signal`, or `playground topic produce` to `dbz-signals`) and verify that all 6 records are in `asgard.public.customers2`.

With `--enable-sql-datagen`, `playground run` injects rows in the `CUSTOMERS` table once the example succeeded, see [Benchmark](#benchmark).

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads rows in the `CUSTOMERS` table (created if it does not exist) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to capture 1M rows inserted in one transaction
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k transactions of one row, then 1M updates of existing rows
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update

# insert, update, then delete the same 500k rows: one drain per phase, compared in the summary and the report
# each deleted row gives a delete event and a tombstone (tombstones.on.delete, default true)
playground connector benchmark --nb-records 500000 --shape bulk,update,delete

# throughput during 2 minutes while batches of 10k rows are inserted continuously
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the rows are loaded, then resumed, and the benchmark measures the time it takes to produce the records. Results are compared with the previous benchmark of the same shape.

`playground run -f debezium-postgres-source.sh --enable-sql-datagen` uses the same load once the example succeeded: one row per transaction (`--shape small-txn`) from 5 parallel sessions for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION` in minutes), logging the rows inserted every 30 seconds.

## SSL setup details

The SSL and mTLS scripts generate a root CA and the PostgreSQL server certificate with `openssl`:

```bash
openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=postgres"
openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
```

A custom image is built from `debezium/postgres:15-alpine` (see `ssl/Dockerfile`):

```dockerfile
FROM debezium/postgres:15-alpine
LABEL "Product"="PostgreSQL (SSL enabled)"
COPY server.key /var/lib/postgresql/server.key
COPY server.crt /var/lib/postgresql/server.crt
COPY ca.crt /var/lib/postgresql/ca.crt
RUN chown postgres /var/lib/postgresql/server.key && \
    chmod 600 /var/lib/postgresql/server.key
```

SSL is enabled in `my-postgres.conf`:

```properties
ssl = on
ssl_cert_file = '/var/lib/postgresql/server.crt'
ssl_key_file = '/var/lib/postgresql/server.key'
ssl_ca_file = '/var/lib/postgresql/ca.crt'
```

and forced in `pg_hba.conf`:

```text
hostssl all all all md5
```

Connector config:

```json
"database.sslmode": "verify-full",
"database.sslrootcert": "/tmp/ca.crt"
```

### Mutual TLS

The client key and certificate are generated too. The key must be converted to PKCS#8 DER, otherwise the JDBC driver fails to read it (see [this thread](https://coderanch.com/t/706596/databases/Connection-string-ssl-client-certificate)):

```bash
openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=myuser"
openssl x509 -req -in /tmp/client.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/client.crt
openssl pkcs8 -topk8 -outform DER -in /tmp/client.key -out /tmp/client.key.pk8 -nocrypt
```

`pg_hba.conf` uses the `cert` method:

```text
hostssl all all all cert clientcert=verify-full
```

Connector config (`database.password` is not set):

```json
"database.sslmode": "verify-full",
"database.sslrootcert": "/tmp/ca.crt",
"database.sslcert": "/tmp/client.crt",
"database.sslkey": "/tmp/client.key.pk8"
```
