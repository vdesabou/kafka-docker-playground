# JDBC IBM DB2 sink connector

## Objective

Quickly test [JDBC IBM DB2](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-sink-connector) connector.


## How to run

Simply run:

```
$ playground run -f ibmdb2-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

with SSL Encryption:

```
$ playground run -f ibmdb2-sink-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

N.B: IBM DB2 Console is reachable at [https://localhost:9443/ibmmq/console/login.html (admin/passw0rd)](https://localhost:9443/ibmmq/console/login.html])

## Details of what the script is doing

`ibmdb2` container is configured with `SAMPLEDB: "true"`, so it is already populated with tables:

```yml
  ibmdb2:
    image: ibmcom/db2:11.5.6.0
    hostname: ibmdb2
    container_name: ibmdb2
    privileged: true
removed
    environment:
      LICENSE: accept
      DB2INST1_PASSWORD: passw0rd
      DBNAME: testdb
      ARCHIVE_LOGS: "false"
      SAMPLEDB: "true"
```

Sending messages to topic `ORDERS`:

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"ID","type":"int"},{"name":"PRODUCT", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

Creating JDBC IBM DB2 sink connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url":"jdbc:db2://ibmdb2:25010/sample",
               "connection.user":"db2inst1",
               "connection.password":"passw0rd",
               "topics": "ORDERS",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/ibmdb2-sink/config | jq .
```

sleep 5

Check data is in IBM DB2:

```bash
docker exec -i ibmdb2 bash << EOF > /tmp/result.log
su - db2inst1
db2 connect to sample user db2inst1 using passw0rd
db2 select ID,PRODUCT,QUANTITY,PRICE from ORDERS
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
```

Results:

```json
Database Connection Information

 Database server        = DB2/LINUXX8664 11.5.6.0
 SQL authorization ID   = DB2INST1
 Local database alias   = SAMPLE


ID PRODUCT      QUANTITY    PRICE
----------- -- ----------- ------
999 foo        100   +5.00000000000000E+001

  1 record(s) selected.

Last login: Wed Sep  8 10:00:28 UTC 2021
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
