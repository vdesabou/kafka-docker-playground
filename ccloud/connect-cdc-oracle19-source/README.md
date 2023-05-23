# Oracle CDC Source (Oracle 19c) Source connector using Confluent Cloud

## Objective

Quickly test [Oracle CDC Source Connector](https://docs.confluent.io/kafka-connect-oracle-cdc/current/) with Oracle 19c and Confluent Cloud.

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip`from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in `./LINUX.X64_193000_db_home.zip`


Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:19.3.0-ee`. It takes about 10 minutes.

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## Note on `redo.log.row.fetch.size`

The connector is configured with `"redo.log.row.fetch.size":1` for demo purpose only. If you're planning to inject more data, it is recommended to increase the value.

Example with included script [`07_generate_customers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/sample-sql-scripts/07_generate_customers.sh.zip) (packaged as `.zip`in order to not be run automatically), which inserts around 7000 customer rows, in that case you would need to set `"redo.log.row.fetch.size":1000`:

```
cd sample-sql-scripts
unzip 07_generate_customers.sh.zip 
cd -
# insert new customer every 500ms
./sample-sql-scripts/07_generate_customers.sh "ORCLCDB" 0.5
# insert new customer every second (default)
./sample-sql-scripts/07_generate_customers.sh "ORCLCDB" 
```

See screencast below:


https://user-images.githubusercontent.com/4061923/139914676-e34fae34-0f5c-4240-9690-d1d486236457.mp4



## How to run

Without SSL:

```
$ playground run -f cdc-oracle19-cdb-table<tab>
```

or

```
$ playground run -f cdc-oracle19-pdb-table<tab>
```

Note:

Using ksqlDB using CLI:

```bash
$ docker exec -i ksqldb-cli ksql http://ksqldb-server:8088
```

## Details of what the script is doing

### CDB table

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "key.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "value.converter.basic.auth.credentials.source": "USER_INFO",

               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3",

               "topic.creation.groups":"redo",
               "topic.creation.redo.include":"redo-log-topic",
               "topic.creation.redo.replication.factor":3,
               "topic.creation.redo.partitions":1,
               "topic.creation.redo.cleanup.policy":"delete",
               "topic.creation.redo.retention.ms":1209600000,
               "topic.creation.default.replication.factor":3,
               "topic.creation.default.partitions":3,
               "topic.creation.default.cleanup.policy":"compact",

               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",

               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "redo.log.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "redo.log.consumer.security.protocol":"SASL_SSL",
               "redo.log.consumer.sasl.mechanism":"PLAIN",

               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb-cloud/config | jq .
```

Verify the topic `ORCLCDB.C__MYUSER.CUSTOMERS`:

```bash
playground topic consume --topic ORCLCDB.C__MYUSER.CUSTOMERS --min-expected-messages 13
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047105216},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1604047105230},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
```

#### PDB table

Grant select on CUSTOMERS table:

```bash
$ docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
     ALTER SESSION SET CONTAINER=ORCLPDB1;
     GRANT select on CUSTOMERS TO C##MYUSER;
EOF
```

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "key.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "value.converter.basic.auth.credentials.source": "USER_INFO",

               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3",

               "topic.creation.groups":"redo",
               "topic.creation.redo.include":"redo-log-topic",
               "topic.creation.redo.replication.factor":3,
               "topic.creation.redo.partitions":1,
               "topic.creation.redo.cleanup.policy":"delete",
               "topic.creation.redo.retention.ms":1209600000,
               "topic.creation.default.replication.factor":3,
               "topic.creation.default.partitions":3,
               "topic.creation.default.cleanup.policy":"compact",

               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.pdb.name": "ORCLPDB1",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",

               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "redo.log.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "redo.log.consumer.security.protocol":"SASL_SSL",
               "redo.log.consumer.sasl.mechanism":"PLAIN",

               "table.inclusion.regex": "ORCLPDB1[.].*[.]CUSTOMERS",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-pdb-cloud/config | jq .
```

Verify the topic `ORCLPDB1.C__MYUSER.CUSTOMERS`:

```bash
playground topic consume --topic ORCLPDB1.C__MYUSER.CUSTOMERS --min-expected-messages 13
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047707934},"UPDATE_TS":{"long":1604047707000},"op_type":"R","table":"ORCLPDB1.C##MYUSER.CUSTOMERS","scn":"1449255"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1604047707939},"UPDATE_TS":{"long":1604047707000},"op_type":"R","table":"ORCLPDB1.C##MYUSER.CUSTOMERS","scn":"1449255"}
```

The above records was present before the connector startup thus the operation type is "R" which means "REFRESH".
Once started, the connector captures the new database changes and stream them into 2 topics:

The "table topic" like `ORCLPDB1.C__MYUSER.CUSTOMERS`
```json
{"ID":"*","FIRST_NAME":{"string":"Frantz"},"LAST_NAME":{"string":"Kafka"},"EMAIL":{"string":"fkafka@confluent.io"},"GENDER":{"string":"Male"},"CLUB_STATUS":{"string":"gold"},"COMMENTS":{"string":"Evil is whatever distracts"},"CREATE_TS":{"long":1619473009476},"UPDATE_TS":{"long":1619473009000},"table":{"string":"ORCLCDB.C##MYUSER.CUSTOMERS"},"scn":{"string":"1449894"},"op_type":{"string":"U"},"op_ts":{"string":"1619473009000"},"current_ts":{"string":"1619473012136"},"row_id":{"string":"AAAR9TAAHAAAACGAAA"},"username":{"string":"C##MYUSER"}}
```
The above event represent the state of the database record after being updated. It captures also some metadata which is not present in the refresh event like scn, operation timestamp, username, etc.

The "technical" event is present in the `redo-log-topic`
```json
{"SCN":{"long":1448360},"START_SCN":{"long":1448360},"COMMIT_SCN":{"long":1448361},"TIMESTAMP":{"long":1619524688000},"START_TIMESTAMP":{"long":1619524688000},"COMMIT_TIMESTAMP":{"long":1619524688000},"XIDUSN":{"long":8},"XIDSLT":{"long":8},"XIDSQN":{"long":725},"XID":{"bytes":"\b\u0000\b\u0000Õ\u0002\u0000\u0000"},"PXIDUSN":{"long":8},"PXIDSLT":{"long":8},"PXIDSQN":{"long":725},"PXID":{"bytes":"\b\u0000\b\u0000Õ\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"UPDATE"},"OPERATION_CODE":{"int":3},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAR9TAAHAAAACHAAF"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":90002},"SESSION_NUM":{"long":867},"SERIAL_NUM":{"long":29292},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal= OS_process_id=3211 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":2},"RBABLK":{"long":192144},"RBABYTE":{"long":100},"UBAFIL":{"long":4},"UBABLK":{"long":16783950},"UBAREC":{"long":36},"UBASQN":{"long":218},"ABS_FILE_NUM":{"long":4},"REL_FILE_NUM":{"long":7},"DATA_BLK_NUM":{"long":135},"DATA_OBJ_NUM":{"long":73555},"DATA_OBJV_NUM":{"long":1},"DATA_OBJD_NUM":{"long":73555},"SQL_REDO":{"string":"update \"C##MYUSER\".\"CUSTOMERS\" set \"CLUB_STATUS\" = 'gold', \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') where \"ID\" = '42' and \"FIRST_NAME\" = 'Frantz' and \"LAST_NAME\" = 'Kafka' and \"EMAIL\" = 'fkafka@confluent.io' and \"GENDER\" = 'Male' and \"CLUB_STATUS\" = 'bronze' and \"COMMENTS\" = 'Evil is whatever distracts' and \"CREATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.678') and \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') and ROWID = 'AAAR9TAAHAAAACHAAF';"},"SQL_UNDO":{"string":"update \"C##MYUSER\".\"CUSTOMERS\" set \"CLUB_STATUS\" = 'bronze', \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') where \"ID\" = '42' and \"FIRST_NAME\" = 'Frantz' and \"LAST_NAME\" = 'Kafka' and \"EMAIL\" = 'fkafka@confluent.io' and \"GENDER\" = 'Male' and \"CLUB_STATUS\" = 'gold' and \"COMMENTS\" = 'Evil is whatever distracts' and \"CREATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.678') and \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') and ROWID = 'AAAR9TAAHAAAACHAAF';"},"RS_ID":{"string":" 0x000002.0002ee90.0064 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":298},"UNDO_VALUE":{"long":299},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":1448361},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"CDB$ROOT"},"SRC_CON_ID":{"long":1},"SRC_CON_UID":{"long":1},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
