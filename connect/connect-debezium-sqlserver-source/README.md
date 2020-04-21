# Debezium SQL Server source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-debezium-sqlserver-source/asciinema.gif?raw=true)

## Objective

Quickly test [Debezium SQL Server](https://docs.confluent.io/current/connect/debezium-connect-sqlserver/index.html#quick-start) connector.




## How to run

Simply run:

```
$ ./sqlserver.sh
```

or with standalone mode:

```
$ ./sqlserver-standalone.sh
```

## Details of what the script is doing


Load inventory.sql to SQL Server

```bash
$ cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'
```


Creating Debezium SQL Server source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
                    "tasks.max": "1",
                    "database.hostname": "sqlserver",
                    "database.port": "1433",
                    "database.user": "sa",
                    "database.password": "Password!",
                    "database.server.name": "server1",
                    "database.dbname" : "testDB",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.inventory"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .
```

Insert one more row:

```bash
$ docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF
```

Verifying topic `server1.dbo.customers`


```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5
```

Results:

```json
{"before":null,"after":{"server1.dbo.customers.Value":{"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com"}},"source":{"version":"0.10.0.Final","connector":"sqlserver","name":"server1","ts_ms":1571914675218,"snapshot":{"string":"true"},"db":"testDB","schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000448:0003"},"event_serial_no":null},"op":"r","ts_ms":{"long":1571914675223}}
{"before":null,"after":{"server1.dbo.customers.Value":{"id":1002,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com"}},"source":{"version":"0.10.0.Final","connector":"sqlserver","name":"server1","ts_ms":1571914675226,"snapshot":{"string":"true"},"db":"testDB","schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000448:0003"},"event_serial_no":null},"op":"r","ts_ms":{"long":1571914675226}}
{"before":null,"after":{"server1.dbo.customers.Value":{"id":1003,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com"}},"source":{"version":"0.10.0.Final","connector":"sqlserver","name":"server1","ts_ms":1571914675231,"snapshot":{"string":"true"},"db":"testDB","schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000448:0003"},"event_serial_no":null},"op":"r","ts_ms":{"long":1571914675231}}
{"before":null,"after":{"server1.dbo.customers.Value":{"id":1004,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org"}},"source":{"version":"0.10.0.Final","connector":"sqlserver","name":"server1","ts_ms":1571914675231,"snapshot":{"string":"last"},"db":"testDB","schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000448:0003"},"event_serial_no":null},"op":"r","ts_ms":{"long":1571914675231}}
{"before":null,"after":{"server1.dbo.customers.Value":{"id":1005,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com"}},"source":{"version":"0.10.0.Final","connector":"sqlserver","name":"server1","ts_ms":1571914677337,"snapshot":{"string":"false"},"db":"testDB","schema":"dbo","table":"customers","change_lsn":{"string":"00000025:00000518:0003"},"commit_lsn":{"string":"00000025:00000518:0005"},"event_serial_no":{"long":1}},"op":"c","ts_ms":{"long":1571914683147}}
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
