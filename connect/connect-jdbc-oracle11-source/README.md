# JDBC Oracle 11 Source connector

## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector with Oracle 11.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)


* Download Oracle Database 11g Release 2 (11.2.0.4) JDBC driver `ojdbc6.jar`from this [page](https://www.oracle.com/database/technologies/jdbcdriver-ucp-downloads.html) and place it in `./ojdbc6.jar`

## How to run

Simply run:

```
$ ./oracle11.sh
```

## Details of what the script is doing

Create the source connector with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
                    "numeric.mapping":"best_fit",
                    "mode":"timestamp",
                    "poll.interval.ms":"1000",
                    "validate.non.null":"false",
                    "table.whitelist":"MYTABLE",
                    "timestamp.column.name":"UPDATE_TS",
                    "topic.prefix":"oracle-",
                    "schema.pattern":"MYUSER",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/oracle-source/config | jq_docker_cli .
```

Verify the topic `oracle-MYTABLE`:

```bash
$ docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic oracle-MYTABLE --from-beginning --max-messages 1
```

Results:

```json
{"ID":1,"DESCRIPTION":"kafka","UPDATE_TS":{"long":1571317782000}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
