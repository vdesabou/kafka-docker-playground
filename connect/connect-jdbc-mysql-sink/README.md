# JDBC MySQL Sink connector



## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#quick-start) connector with MySQL.

## How to run

Without SSL:

```
$ just use <playground run> command and search for mysql-sink.sh in this folder
```

with SSL encryption:

```
$ just use <playground run> command and search for mysql-sink-ssl.sh in this folder
```

with SSL encryption + Mutual TLS authentication:

```
$ just use <playground run> command and search for mysql-sink-mtls.sh in this folder
```
