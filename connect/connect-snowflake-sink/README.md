# Snowflake Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-snowflake-sink/asciinema.gif?raw=true)

## Objective

Quickly test [Snowflake Sink](https://docs.snowflake.com/en/user-guide/kafka-connector.html) connector.



## Register a trial account

Go to [Snowflakel](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

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
DROP DATABASE IF EXISTS KAFKA_DB;
CREATE OR REPLACE DATABASE KAFKA_DB COMMENT = 'Database for KafkaConnect demo';
EOF
```

Create a Snowflake ROLE

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS KAFKA_CONNECTOR_ROLE;
CREATE ROLE KAFKA_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE KAFKA_DB TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE KAFKA_DB TO ACCOUNTADMIN;
GRANT USAGE ON SCHEMA KAFKA_DB.PUBLIC TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA KAFKA_DB.PUBLIC TO KAFKA_CONNECTOR_ROLE;
GRANT USAGE ON SCHEMA KAFKA_DB.PUBLIC TO ROLE ACCOUNTADMIN;
GRANT CREATE TABLE ON SCHEMA KAFKA_DB.PUBLIC TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA KAFKA_DB.PUBLIC TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE PIPE ON SCHEMA KAFKA_DB.PUBLIC TO ROLE KAFKA_CONNECTOR_ROLE;
EOF
```

Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE WAREHOUSE KAFKA_ADMIN_WAREHOUSE
  WAREHOUSE_SIZE = 'XSMALL'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 1
  SCALING_POLICY = 'STANDARD'
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for Kafka admin activities';
GRANT USAGE ON WAREHOUSE KAFKA_ADMIN_WAREHOUSE TO ROLE KAFKA_CONNECTOR_ROLE;
EOF
```

Create a Snowflake USER

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE ACCOUNTADMIN;
DROP USER IF EXISTS KAFKA_DEMO;
CREATE USER KAFKA_DEMO
 PASSWORD = 'Password123!'
 LOGIN_NAME = KAFKA_DEMO
 DISPLAY_NAME = KAFKA_DEMO
 DEFAULT_WAREHOUSE = KAFKA_ADMIN_WAREHOUSE
 DEFAULT_ROLE = KAFKA_CONNECTOR_ROLE
 DEFAULT_NAMESPACE = KAFKA_DB
 MUST_CHANGE_PASSWORD = FALSE
 RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY";
GRANT ROLE KAFKA_CONNECTOR_ROLE TO USER KAFKA_DEMO;
EOF
```

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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
$ docker exec -e SNOWFLAKE_URL="$SNOWFLAKE_URL" -e RSA_PRIVATE_KEY="$RSA_PRIVATE_KEY" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
               "topics": "test_table",
               "tasks.max": "1",
               "snowflake.url.name":"'"$SNOWFLAKE_URL"'",
               "snowflake.user.name":"KAFKA_DEMO",
               "snowflake.user.role":"KAFKA_CONNECTOR_ROLE",
               "snowflake.private.key":"'"$RSA_PRIVATE_KEY"'",
               "snowflake.private.key.passphrase": "confluent",
               "snowflake.database.name":"KAFKA_DB",
               "snowflake.schema.name":"PUBLIC",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "com.snowflake.kafka.connector.records.SnowflakeAvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/snowflake-sink/config | jq .
```

Confirm that the messages were delivered to the Snowflake table (logged as `KAFKA_DEMO` user)

```bash
docker run --rm -i -v $PWD/snowflake_key.p8:/tmp/rsa_key.p8 -e SNOWSQL_PRIVATE_KEY_PASSPHRASE=confluent snowsql:latest --username KAFKA_DEMO -a $SNOWFLAKE_ACCOUNT_NAME --private-key-path /tmp/rsa_key.p8 << EOF
USE ROLE KAFKA_CONNECTOR_ROLE;
USE DATABASE KAFKA_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE KAFKA_ADMIN_WAREHOUSE;
SELECT * FROM KAFKA_DB.PUBLIC.TEST_TABLE;
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
