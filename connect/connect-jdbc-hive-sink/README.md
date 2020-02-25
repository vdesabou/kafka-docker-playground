# JDBC Hive sink connector

* Using Apache Hive JDBC driver

**NOT WORKING**: addBatch() method is not implemented on Hive, see [link](https://stackoverflow.com/questions/50984798/batch-insert-in-hive-using-hive-jdbc) and [link](https://issues.apache.org/jira/browse/HIVE-16221)

* Using [Progress DataDirect JDBC driver](https://documentation.progress.com/output/DataDirect/jdbcquickstarts/hivejdbc_quickstart/index.html#page/jdbchivequick%2Fquick-start-3a-progress-datadirect-for-jdbc-for-ap.html%23)

A working version is available with [Progress DataDirect JDBC driver](https://documentation.progress.com/output/DataDirect/jdbcquickstarts/hivejdbc_quickstart/index.html#page/jdbchivequick%2Fquick-start-3a-progress-datadirect-for-jdbc-for-ap.html%23), you must download install the driver manually and place it in `./hive.jar`

## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#jdbc-sink-connector-for-cp) connector with Hive.


## How to run

Simply run:

```
$ ./hive-sink.sh (not working)
```

or

```
$ ./hive-sink-datadirect.sh (working, but with license)
```


## Details of what the script is doing


Create table in hive


```bash
$ docker exec -i hive-server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 << EOF
CREATE TABLE pokes (foo INT, bar STRING);
EOF
```

Sending messages to topic `pokes`


```bash
$ seq -f "{\"foo\": %g,\"bar\": \"a string\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic pokes --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"foo","type":"int"},{"name":"bar","type":"string"}]}'
```


Using Apache Hive JDBC driver:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max" : "1",
               "connection.url": "jdbc:hive2://hive-server:10000/default",
               "auto.create": "true",
               "auto.evolve": "true",
               "topics": "pokes",
               "pk.mode": "record_value",
               "pk.fields": "foo",
               "table.name.format": "default.${topic}"
          }' \
     http://localhost:8083/connectors/jdbc-hive-sink/config | jq .
```

Using DataDirect JDBC driver:

Check data is in hive
```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max" : "1",
               "connection.url": "jdbc:datadirect:hive://hive-server:10000;DatabaseName=default;User=hive;Password=hive;TransactionMode=ignore",
               "auto.create": "true",
               "auto.evolve": "true",
               "topics": "pokes",
               "pk.mode": "record_value",
               "pk.fields": "foo",
               "table.name.format": "default.${topic}"
          }' \
     http://localhost:8083/connectors/jdbc-hive-sink/config | jq .
```

```bash
$ ${DIR}/presto.jar --server localhost:18080 --catalog hive --schema default << EOF
select * from pokes;
EOF
```

Not working with Apache Hive JDBC driver:

```log
[2020-02-25 10:43:07,923] ERROR WorkerSinkTask{id=jdbc-hive-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
org.apache.kafka.connect.errors.RetriableException: java.sql.SQLException: java.sql.SQLFeatureNotSupportedException: Method not supported

        at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:93)
        at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:539)
        at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:322)
        at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
        at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
        at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
        at java.lang.Thread.run(Thread.java:748)
Caused by: java.sql.SQLException: java.sql.SQLFeatureNotSupportedException: Method not supported
```

Working with [Progress DataDirect JDBC driver](https://documentation.progress.com/output/DataDirect/jdbcquickstarts/hivejdbc_quickstart/index.html#page/jdbchivequick%2Fquick-start-3a-progress-datadirect-for-jdbc-for-ap.html%23):

```
presto:default> select * from pokes;
 foo |   bar
-----+----------
   1 | a string
   2 | a string
   3 | a string
   4 | a string
   5 | a string
   6 | a string
   7 | a string
   8 | a string
   9 | a string
  10 | a string
(10 rows)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
