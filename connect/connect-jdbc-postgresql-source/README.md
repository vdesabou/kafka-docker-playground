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
| `postgres.sh` | No SSL, PostgreSQL 15. Supports `--enable-sql-datagen` |
| `postgres-ssl.sh` | SSL encryption with server certificate verification (`sslmode=verify-full`), custom PostgreSQL 10 image |
| `postgres-mtls.sh` | SSL encryption + mutual TLS: the client authenticates with a certificate instead of a password |

To inject data for 10 minutes with the Java SQL datagen (built from `postgres-datagen/`) after the connector is created:

```bash
playground run -f postgres.sh --enable-sql-datagen
```

## What the script does

1. SSL / mTLS variants only: generates a root CA and the PostgreSQL server certificate (plus a client certificate for mTLS) with `openssl`, and builds a PostgreSQL image with SSL enabled (see below).
2. Starts the environment with a `postgres` container.
3. Creates the `CUSTOMERS` table (`id` SERIAL, `update_ts` maintained by a `BEFORE UPDATE` trigger), inserts 20 rows, then one more.
4. Creates the source connector (`postgres-source`, `postgres-source-ssl` or `postgres-source-mtls`) in `timestamp+incrementing` mode on `update_ts` / `id`, with `topic.prefix=postgres-`.
5. Verifies that records land in topic `postgres-customers` with `playground topic consume`.
6. `postgres.sh` with `--enable-sql-datagen`: runs the SQL datagen for 10 minutes.

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
