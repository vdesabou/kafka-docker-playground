# JDBC MariaDB Sink connector



## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#quick-start) connector with MariaDB.

## How to run


```
$ just use <playground run> command and search for mariadb-sink.sh in this folder
```

## Details of what the script is doing

Creating MariaDB sink connector

```bash
playground connector create-or-update --connector mariadb-sink  << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:mariadb://mariadb:3306/db?user=user&password=password&useSSL=false",
     "topics": "orders",
     "auto.create": "true"
}
```

Sending messages to topic orders

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```


Describing the `orders` table in DB `db`:

```bash
$ docker exec mariadb bash -c "mariadb --user=user --password=password db -e 'describe orders;'"
```

Results:
```
Field   Type    Null    Key     Default Extra
id      int(11) NO              NULL
product text    NO              NULL
quantity        int(11) NO              NULL
price   float   NO              NULL
```

Show content of `orders` table:

```bash
$ docker exec mariadb bash -c "mariadb --user=user --password=password db -e 'select * from orders;'"
```

Results:

```
id      product quantity        price
1       Norwood 2       0.555599
2       foo     2       0.865833
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
