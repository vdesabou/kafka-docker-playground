# JDBC Oracle 11 Source connector



## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector with Oracle 11.

* If you're using a JDBC connector version before `10.0.0`, you need to download Oracle Database 11g Release 2 (11.2.0.4) JDBC driver `ojdbc6.jar`from this [page](https://www.oracle.com/database/technologies/jdbcdriver-ucp-downloads.html) and place it in `./ojdbc6.jar`

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

## Performance testing

You can set environment variable `SQL_DATAGEN` before running the example and it will use a Java based datagen tool:

Example:

```
DURATION=10
log "Injecting data for $DURATION minutes"
docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username C##MYUSER --password mypassword --sidOrServerName sid --sidOrServerNameVal XE --maxPoolSize 10 --durationTimeMin $DURATION"
```

You can increase thoughtput with `maxPoolSize`.

## How to run

Simply run:

```
$ playground run -f oracle11<tab>
```

## Details of what the script is doing

Create the source connector with:

```bash
$ curl -X PUT \
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
     http://localhost:8083/connectors/oracle-source/config | jq .
```

Verify the topic `oracle-MYTABLE`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-MYTABLE --from-beginning --max-messages 1
```

Results:

```json
{"ID":1,"DESCRIPTION":"kafka","UPDATE_TS":{"long":1571317782000}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
