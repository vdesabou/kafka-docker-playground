# CDC Oracle 12 Source connector

<!-- ![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-jdbc-oracle12-source/asciinema.gif?raw=true) -->

## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector with Oracle 12.

* **FIXTHIS**: unzip `confluentinc-kafka-connect-oracle-cdc-0.1.0-preview.zip`
* Download Oracle Database 12c Release 2 (12.2.0.1.0) for Linux x86-64 `linuxx64_12201_database.zip`from this [page](https://www.oracle.com/database/technologies/oracle12c-linux-12201-downloads.html) and place it in `./linuxx64_12201_database.zip`

Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:12.2.0.1-ee`. It takes about 20 minutes.

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

## How to run

Simply run:

```
$ ./cdc-oracle12.sh
```

## Details of what the script is doing

Build `oracle/database:12.2.0.1-ee` Docker image if required.

Wait (up to 15 minutes) that Oracle DB is up

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":1,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.database": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "_table.topic.name.template_":"Using template vars to set change event topic for each table",
               "table.topic.name.template": "${databaseName}.${tableName}",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source/config | jq .
```

Verify the topic `FIXTHIS`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.CUSTOMERS --from-beginning --max-messages 2
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1600969027396},"UPDATE_TS":{"long":1600969027000},"op_type":"R","table":"C##MYUSER.CUSTOMERS","scn":"1450294"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1600969027402},"UPDATE_TS":{"long":1600969027000},"op_type":"R","table":"C##MYUSER.CUSTOMERS","scn":"1450294"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

## Troubleshooting

You might see the following timeout error on Mac OS

```
08:56:16 Verifying topic ORCLCDB.CUSTOMERS
./cdc-oracle12.sh: line 94: timeout: command not found
```

Please install ``coreutils`` with the following commands

```bash
brew install coreutils
sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout
```



