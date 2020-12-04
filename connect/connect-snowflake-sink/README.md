# Snowflake Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-snowflake-sink/asciinema.gif?raw=true)

## Objective

Quickly test [Snowflake Sink](https://docs.snowflake.com/en/user-guide/kafka-connector.html) connector.



## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

## How to run

Simply run:

```bash
$ ./snowflake-sink.sh <SNOWFLAKE_ACCOUNT_NAME> <SNOWFLAKE_USERNAME> <SNOWFLAKE_PASSWORD>
```

Note: you can also export these values as environment variable

## Details of what the script is doing

Create a Snowflake DB

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS PLAYGROUND_DB;
CREATE OR REPLACE DATABASE PLAYGROUND_DB COMMENT = 'Database for Docker Playground';
EOF
```

Create a Snowflake ROLE

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS PLAYGROUND_CONNECTOR_ROLE;
CREATE ROLE PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE PLAYGROUND_DB TO ROLE PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE PLAYGROUND_DB TO ACCOUNTADMIN;
GRANT USAGE ON SCHEMA PLAYGROUND_DB.PUBLIC TO ROLE PLAYGROUND_CONNECTOR_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA PLAYGROUND_DB.PUBLIC TO PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON SCHEMA PLAYGROUND_DB.PUBLIC TO ROLE ACCOUNTADMIN;
GRANT CREATE TABLE ON SCHEMA PLAYGROUND_DB.PUBLIC TO ROLE PLAYGROUND_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA PLAYGROUND_DB.PUBLIC TO ROLE PLAYGROUND_CONNECTOR_ROLE;
GRANT CREATE PIPE ON SCHEMA PLAYGROUND_DB.PUBLIC TO ROLE PLAYGROUND_CONNECTOR_ROLE;
EOF
```

Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SYSADMIN;
CREATE OR REPLACE WAREHOUSE PLAYGROUND_WAREHOUSE
  WAREHOUSE_SIZE = 'XSMALL'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 1
  SCALING_POLICY = 'STANDARD'
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for Kafka Playground';
GRANT USAGE ON WAREHOUSE PLAYGROUND_WAREHOUSE TO ROLE PLAYGROUND_CONNECTOR_ROLE;
EOF
```

Create a Snowflake USER

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE USERADMIN;
DROP USER IF EXISTS PLAYGROUND_USER;
CREATE USER PLAYGROUND_USER
 PASSWORD = 'Password123!'
 LOGIN_NAME = PLAYGROUND_USER
 DISPLAY_NAME = PLAYGROUND_USER
 DEFAULT_WAREHOUSE = PLAYGROUND_WAREHOUSE
 DEFAULT_ROLE = PLAYGROUND_CONNECTOR_ROLE
 DEFAULT_NAMESPACE = PLAYGROUND_DB
 MUST_CHANGE_PASSWORD = FALSE
 RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY";
USE ROLE SECURITYADMIN;
GRANT ROLE PLAYGROUND_CONNECTOR_ROLE TO USER PLAYGROUND_USER;
EOF
```

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi

Sending messages to topic `test_table`

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

Creating Snowflake Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
               "topics": "test_table",
               "tasks.max": "1",
               "snowflake.url.name":"'"$SNOWFLAKE_URL"'",
               "snowflake.user.name":"PLAYGROUND_USER",
               "snowflake.user.role":"PLAYGROUND_CONNECTOR_ROLE",
               "snowflake.private.key":"'"$RSA_PRIVATE_KEY"'",
               "snowflake.private.key.passphrase": "confluent",
               "snowflake.database.name":"PLAYGROUND_DB",
               "snowflake.schema.name":"PUBLIC",
               "buffer.count.records": "3",
               "buffer.flush.time" : "10",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/snowflake-sink/config | jq .
```

Confirm that the messages were delivered to the Snowflake table (logged as `KAFKA_DEMO` user)

```bash
$ docker run --rm -i -e SNOWSQL_PWD='Password123!' -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username PLAYGROUND_USER -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE PLAYGROUND_WAREHOUSE;
SELECT * FROM PLAYGROUND_DB.PUBLIC.TEST_TABLE;
EOF
```

Results:

```
+--------------------------------+--------------------------+
| RECORD_METADATA                | RECORD_CONTENT           |
|--------------------------------+--------------------------|
| {                              | {                        |
|   "CreateTime": 1586360912100, |   "u_name": "scissors",  |
|   "offset": 0,                 |   "u_price": 2.75,       |
|   "partition": 0,              |   "u_quantity": 3        |
|   "schema_id": 1,              | }                        |
|   "topic": "test_table"        |                          |
| }                              |                          |
| {                              | {                        |
|   "CreateTime": 1586360912119, |   "u_name": "tape",      |
|   "offset": 1,                 |   "u_price": 0.99,       |
|   "partition": 0,              |   "u_quantity": 10       |
|   "schema_id": 1,              | }                        |
|   "topic": "test_table"        |                          |
| }                              |                          |
| {                              | {                        |
|   "CreateTime": 1586360912119, |   "u_name": "notebooks", |
|   "offset": 2,                 |   "u_price": 1.99,       |
|   "partition": 0,              |   "u_quantity": 5        |
|   "schema_id": 1,              | }                        |
|   "topic": "test_table"        |                          |
| }                              |                          |
+--------------------------------+--------------------------+
3 Row(s) produced. Time Elapsed: 0.811s
Goodbye!
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
