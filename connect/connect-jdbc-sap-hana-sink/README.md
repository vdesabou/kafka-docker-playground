# JDBC SAP HANA Sink connector



## Objective

Quickly test [JDBC Sap Hana Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector) connector.


## How to run

Simply run:

```
$ playground run -f sap-hana-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Sending records to testtopic topic:

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic testtopic --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
{"ID": 222}|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF
```

Creating SAP HANA Sink connector:

```bash
playground connector create-or-update --connector jdbc-sap-hana-sink << EOF
{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "topics": "testtopic",
               "connection.url": "jdbc:sap://sap:39041/?databaseName=HXE&reconnect=true&statementCacheSize=512",
               "connection.user": "LOCALDEV",
               "connection.password" : "Localdev1",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "auto.create": "true"
          }
EOF
```

Check data is in SAP HANA:

```bash
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1  > /tmp/result.log  2>&1 <<-EOF
select * from "LOCALDEV"."testtopic";
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
```

Results:

```
Welcome to the SAP HANA Database interactive terminal.
                                           
Type:  \h for help with commands          
       \q to quit                         

ID,product,quantity,price
111,"foo",100,50
222,"bar",100,50
2 rows selected (overall time 1145 usec; server time 251 usec)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
