# Oracle CDC Source (Oracle 11) Source connector

## Objective

Quickly test [Oracle CDC Source Connector](https://docs.confluent.io/kafka-connect-oracle-cdc/current/) with Oracle 11.

## Note on `redo.log.row.fetch.size`

The connector is configured with `"redo.log.row.fetch.size":1` for demo purpose only. If you're planning to inject more data, it is recommended to increase the value.

Example with included script [`07_generate_customers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/sample-sql-scripts/07_generate_customers.sh.zip) (packaged as `.zip`in order to not be run automatically), which inserts around 7000 customer rows, in that case you would need to set `"redo.log.row.fetch.size":1000`:

```
cd sample-sql-scripts
unzip 07_generate_customers.sh.zip 
cd -
# insert new customer every 500ms
./sample-sql-scripts/07_generate_customers.sh 0.5
# insert new customer every second (default)
./sample-sql-scripts/07_generate_customers.sh 
```

See screencast below:


https://user-images.githubusercontent.com/4061923/139914676-e34fae34-0f5c-4240-9690-d1d486236457.mp4


## How to run

```
$ ./cdc-oracle11-source.sh
```

Note:

Using ksqlDB using CLI:

```bash
$ docker exec -i ksqldb-cli ksql http://ksqldb-server:8088
```

## Details of what the script is doing

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "XE",
               "oracle.username": "MYUSER",
               "oracle.password": "password",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1
          }' \
     http://localhost:8083/connectors/cdc-oracle11-source/config | jq .
```

Verify the topic `XE.MYUSER.CUSTOMERS`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic XE.MYUSER.CUSTOMERS --from-beginning --max-messages 2
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047105216},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1604047105230},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
