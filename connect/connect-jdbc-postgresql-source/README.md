# JDBC PostgreSQL source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with PostgreSQL.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f postgres.sh
```

| Script | Description |
| --- | --- |
| `postgres.sh` | No SSL, PostgreSQL 15 |
| `postgres-ssl.sh` | SSL encryption with server certificate verification (`sslmode=verify-full`), custom PostgreSQL 10 image |
| `postgres-mtls.sh` | SSL encryption + mutual TLS: the client authenticates with a certificate instead of a password |
| `postgres-orders.sh` | No SSL, a table of your own: an `orders` table with its own benchmark load, [`benchmark-load-orders.bash`](benchmark-load-orders.bash) (see below) |

With `--enable-sql-datagen`, `playground run` injects rows in the `CUSTOMERS` table for 10 minutes once the example succeeded (see [Benchmark](#benchmark)):

```bash
playground run -f postgres.sh --enable-sql-datagen

# inject rows for 2 minutes only
SQL_DATAGEN_DURATION=2 playground run -f postgres.sh --enable-sql-datagen
```

## What the script does

1. SSL / mTLS variants only: generates a root CA and the PostgreSQL server certificate (plus a client certificate for mTLS) with `openssl`, and builds a PostgreSQL image with SSL enabled (see below).
2. Starts the environment with a `postgres` container.
3. Creates the `CUSTOMERS` table (`id` SERIAL, `update_ts` maintained by a `BEFORE UPDATE` trigger), inserts 20 rows, then one more.
4. Creates the source connector (`postgres-source`, `postgres-source-ssl` or `postgres-source-mtls`) in `timestamp+incrementing` mode on `update_ts` / `id`, with `topic.prefix=postgres-`.
5. Verifies that records land in topic `postgres-customers` with `playground topic consume`.

`postgres-orders.sh` creates an `orders` table instead (3 rows), with the connector `postgres-orders-source` in `incrementing` mode on `id`, and verifies topic `postgres-orders`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads rows in the `CUSTOMERS` table (created if it does not exist) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to capture 1M rows inserted in one transaction
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k transactions of one row, then 1M updates of existing rows
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update

# throughput and end-to-end latency (kafka timestamp - create_ts) during 2 minutes while batches of 10k rows are inserted continuously
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the rows are loaded, then resumed, and the benchmark measures the time it takes to produce the records. Results are compared with the previous benchmark of the same shape.

`postgres-orders.sh` reads another table: its load is [`benchmark-load-orders.bash`](benchmark-load-orders.bash), selected with `BENCHMARK_LOAD_SCRIPT` (it inserts rows only, the connector is in `incrementing` mode):

```bash
playground run -f postgres-orders.sh
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --nb-records 1000000
```

This is how a reproduction model loads a table of its own: a `benchmark-load-<ticket>.bash` next to its script, see "A table of your own" in the [documentation](https://kafka-docker-playground.io/#/reusables?id=a-table-of-your-own-reproduction-models).

`playground run -f postgres.sh --enable-sql-datagen` uses the same load once the example succeeded: one row per transaction (`--shape small-txn`) from 5 parallel sessions for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION` in minutes), logging the rows inserted every 30 seconds.

## SSL setup details

### SSL encryption

Create a root certificate authority (CA):

```bash
openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
```

Generate the PostgreSQL server key and certificate:

```bash
openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=postgres"
openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
```

Custom image built from `postgres:10` (`ssl/Dockerfile`):

```dockerfile
FROM postgres:10
LABEL "Product"="PostgreSQL (SSL enabled)"
COPY server.key /var/lib/postgresql/server.key
COPY server.crt /var/lib/postgresql/server.crt
COPY ca.crt /var/lib/postgresql/ca.crt
RUN chown postgres /var/lib/postgresql/server.key && \
    chmod 600 /var/lib/postgresql/server.key
```

Enable SSL (`my-postgres.conf`):

```text
ssl = on
ssl_cert_file = '/var/lib/postgresql/server.crt'
ssl_key_file = '/var/lib/postgresql/server.key'
ssl_ca_file = '/var/lib/postgresql/ca.crt'
```

Force SSL (`pg_hba.conf`):

```text
hostssl all all all md5
```

Connection URL:

```json
"connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&sslmode=verify-full&sslrootcert=/tmp/ca.crt"
```

### SSL encryption + mutual TLS

Generate the client key and certificate. The key must be converted to PKCS#8 DER, otherwise the driver fails (see [this thread](https://coderanch.com/t/706596/databases/Connection-string-ssl-client-certificate)):

```bash
openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=myuser"
openssl x509 -req -in /tmp/client.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/client.crt
openssl pkcs8 -topk8 -outform DER -in /tmp/client.key -out /tmp/client.key.pk8 -nocrypt
```

Force certificate authentication (`pg_hba.conf`):

```text
hostssl all all all cert clientcert=1
```

Connection URL:

```json
"connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&sslmode=verify-full&sslrootcert=/tmp/ca.crt&sslcert=/tmp/client.crt&sslkey=/tmp/client.key.pk8"
```
