# Debezium PostgreSQL source connector



## Objective

Quickly test [Debezium PostGreSQL](https://docs.confluent.io/current/connect/debezium-connect-postgres/index.html#quick-start) connector.

## How to run

Simply run:

Without SSL:

```
$ playground run -f debezium-postgres-source<tab>
```

with SSL encryption:

```
$ playground run -f debezium-postgres-source-ssl<tab>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f debezium-postgres-source-mtls<tab>
```

## Details of what the script is doing

Show content of CUSTOMERS table:

```bash
$ docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"
```

Adding an element to the table

```bash
$ docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"
```


Show content of CUSTOMERS table:

```bash
$ docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"
```

### Without SSL

Creating Debezium PostgreSQL source connector

```bash
playground connector create-or-update --connector debezium-postgres-source << EOF
{
                "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                "tasks.max": "1",
                "database.hostname": "postgres",
                "database.port": "5432",
                "database.user": "myuser",
                "database.password": "mypassword",
                "database.dbname" : "postgres",

                "_comment": "old version before 2.x",
                "database.server.name": "asgard",
                "_comment": "new version since 2.x",
                "topic.prefix": "asgard",

                "key.converter" : "io.confluent.connect.avro.AvroConverter",
                "key.converter.schema.registry.url": "http://schema-registry:8081",
                "value.converter" : "io.confluent.connect.avro.AvroConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "transforms": "addTopicSuffix",
                "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                "transforms.addTopicSuffix.regex":"(.*)",
                "transforms.addTopicSuffix.replacement": "\$1-raw"
          }
EOF
```

Verifying topic asgard.public.customers-raw

```bash
playground topic consume --topic asgard.public.customers-raw --min-expected-messages 5 --timeout 60
```

Result is:

```json
{
    "before": null,
    "after": {
        "asgard.public.customers.Value": {
            "id": 5,
            "first_name": {
                "string": "Hansiain"
            },
            "last_name": {
                "string": "Coda"
            },
            "email": {
                "string": "hcoda4@senate.gov"
            },
            "gender": {
                "string": "Male"
            },
            "club_status": {
                "string": "platinum"
            },
            "comments": {
                "string": "Centralized full-range approach"
            },
            "create_ts": {
                "long": 1570208046048403
            },
            "update_ts": {
                "long": 1570208046048403
            }
        }
    },
    "source": {
        "version": {
            "string": "0.9.5.Final"
        },
        "connector": {
            "string": "postgresql"
        },
        "name": "asgard",
        "db": "postgres",
        "ts_usec": {
            "long": 1570208093526000
        },
        "txId": {
            "long": 580
        },
        "lsn": {
            "long": 24523120
        },
        "schema": {
            "string": "public"
        },
        "table": {
            "string": "customers"
        },
        "snapshot": {
            "boolean": true
        },
        "last_snapshot_record": {
            "boolean": false
        },
        "xmin": null
    },
    "op": "r",
    "ts_ms": {
        "long": 1570208093526
    }
}
```

### With SSL

Creating a Root Certificate Authority (CA)

```bash
openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
```

Generate the PostgreSQL server key and certificate

```bash
openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=postgres"
openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
```

Build custom image from `debezium/postgres:15-alpine`:

```dockerfile
FROM debezium/postgres:15-alpine
LABEL "Product"="PostgreSQL (SSL enabled)"
COPY server.key /var/lib/postgresql/server.key
COPY server.crt /var/lib/postgresql/server.crt
COPY ca.crt /var/lib/postgresql/ca.crt
RUN chown postgres /var/lib/postgresql/server.key && \
    chmod 600 /var/lib/postgresql/server.key
```

Enable ssl (`my-postgres.conf`):

```
ssl = on
ssl_cert_file = '/var/lib/postgresql/server.crt'
ssl_key_file = '/var/lib/postgresql/server.key'
ssl_ca_file = '/var/lib/postgresql/ca.crt'
```

Force SSL (`pg_hba.conf`):

```
# force SSL
hostssl all all all md5
```

Connector config has:

```json
    "database.sslmode": "verify-full",
    "database.sslrootcert": "/tmp/ca.crt",
```

### With SSL encryption + Mutual TLS auth

Generating the Client Key and Certificate

```bash
openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=myuser"
openssl x509 -req -in /tmp/client.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/client.crt
# need to use pk8, otherwise I got this issue https://coderanch.com/t/706596/databases/Connection-string-ssl-client-certificate
openssl pkcs8 -topk8 -outform DER -in /tmp/client.key -out /tmp/client.key.pk8 -nocrypt
```

Force SSL (`pg_hba.conf`), see `cert` option:

```
# force SSL
hostssl all all all cert clientcert=1
```

Connector config has (`database.password` is not set anymore):

```json
    "database.sslmode": "verify-full",
    "database.sslrootcert": "/tmp/ca.crt",
    "database.sslcert": "/tmp/client.crt",
    "database.sslkey": "/tmp/client.key.pk8",
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
