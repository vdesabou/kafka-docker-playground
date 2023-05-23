# JDBC IBM DB2 source connector

## Objective

Quickly test [JDBC IBM DB2](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.


## How to run

Simply run:

```
$ playground run -f ibmdb2-source<tab>
```

with SSL Encryption:

```
$ playground run -f ibmdb2-source-ssl<tab>
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

List tables

```bash
$ docker exec -i ibmdb2 bash << EOF
su - db2inst1
db2 connect to sample user db2inst1 using passw0rd
db2 LIST TABLES
EOF
```

Creating JDBC IBM DB2 source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url":"jdbc:db2://ibmdb2:25010/sample",
               "connection.user":"db2inst1",
               "connection.password":"passw0rd",
               "mode": "bulk",
               "topic.prefix": "db2-",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/ibmdb2-source/config | jq .
```

Verifying topic `db2-PURCHASEORDER`


```bash
playground topic consume --topic db2-PURCHASEORDER --expected-messages 2
```

Results:

```json
{"POID":5000,"STATUS":"Unshipped","CUSTID":{"long":1002},"ORDERDATE":{"int":13197},"PORDER":{"string":"<PurchaseOrder PoNum=\"5000\" OrderDate=\"2006-02-18\" Status=\"Unshipped\"><item><partid>100-100-01</partid><name>Snow Shovel, Basic 22 inch</name><quantity>3</quantity><price>9.99</price></item><item><partid>100-103-01</partid><name>Snow Shovel, Super Deluxe 26 inch</name><quantity>5</quantity><price>49.99</price></item></PurchaseOrder>"},"COMMENTS":{"string":"THIS IS A NEW PURCHASE ORDER"}}
{"POID":5001,"STATUS":"Shipped","CUSTID":{"long":1003},"ORDERDATE":{"int":12817},"PORDER":{"string":"<PurchaseOrder PoNum=\"5001\" OrderDate=\"2005-02-03\" Status=\"Shipped\"><item><partid>100-101-01</partid><name>Snow Shovel, Deluxe 24 inch</name><quantity>1</quantity><price>19.99</price></item><item><partid>100-103-01</partid><name>Snow Shovel, Super Deluxe 26 inch</name><quantity>2</quantity><price>49.99</price></item><item><partid>100-201-01</partid><name>Ice Scraper, Windshield 4 inch</name><quantity>1</quantity><price>3.99</price></item></PurchaseOrder>"},"COMMENTS":{"string":"THIS IS A NEW PURCHASE ORDER"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
