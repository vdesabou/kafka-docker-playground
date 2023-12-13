# JDBC PostgreSQL source connector



## Objective

Quickly test [JDBC PostGreSQL](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.


## How to run

Without SSL:

```
$ playground run -f postgres<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

with SSL encryption:

```
$ playground run -f postgres-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f postgres-mtls<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
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

Creating JDBC PostgreSQL source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "postgres-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/postgres-source/config | jq .
```

Verifying topic `postgres-customers`

```bash
playground topic consume --topic postgres-customers --min-expected-messages 5 --timeout 60
```

Result is:

```json
{
    "id": 1,
    "first_name": {
        "string": "Rica"
    },
    "last_name": {
        "string": "Blaisdell"
    },
    "email": {
        "string": "rblaisdell0@rambler.ru"
    },
    "gender": {
        "string": "Female"
    },
    "club_status": {
        "string": "bronze"
    },
    "comments": {
        "string": "Universal optimal hierarchy"
    },
    "create_ts": {
        "long": 1571844488922
    },
    "update_ts": {
        "long": 1571844488922
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

Build custom image from `postgres:10`:

```dockerfile
FROM postgres:10
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

`connection.url` is `"connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&sslmode=verify-full&sslrootcert=/tmp/ca.crt"`

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

`connection.url` is `"connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&sslmode=verify-full&sslrootcert=/tmp/ca.crt&sslcert=/tmp/client.crt&sslkey=/tmp/client.key.pk8"`

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
