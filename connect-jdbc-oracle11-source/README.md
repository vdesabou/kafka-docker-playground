# JDBC Oracle 11 Source connector

## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) Oracle 11 connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

* Download Oracle Database 11g Release 2 (11.2.0.4) JDBC driver `ojdbc6.jar`from this [page](https://www.oracle.com/database/technologies/jdbcdriver-ucp-downloads.html) and place it in `./ojdbc6.jar`

## How to run

Simply run:

```
$ ./oracle11.sh
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
