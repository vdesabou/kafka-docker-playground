# JDBC PostgreSQL sink connector



## Objective

Quickly test [JDBC PostGreSQL](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#kconnect-long-jdbc-sink-connector) connector.




## How to run

Simply run:

Without SSL:

```
$ playground run -f postgres-sink<tab>
```

with SSL encryption:

```
$ playground run -f postgres-sink-ssl<tab>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f postgres-sink-mtls<tab>
```

## Details of what the script is doing

### Without SSL

Sending messages to topic orders

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Creating JDBC PostgreSQL sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .
```

Show content of ORDERS table:

```bash
$ docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERS'"
```

Results:

```
 product | quantity | price | id
---------+----------+-------+-----
 foo     |      100 |    50 | 999
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
