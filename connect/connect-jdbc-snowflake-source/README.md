# JDBC Snowflake Source connector


## Objective

Quickly test [JDBC Snowflake Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.

## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

## How to run

Simply run:

```bash
$ playground run -f jdbc-snowflake-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <SNOWFLAKE_ACCOUNT_NAME> <SNOWFLAKE_USERNAME> <SNOWFLAKE_PASSWORD>
```

Note: you can also export these values as environment variable

## Details of what the script is doing

Create a Snowflake DB

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS $PLAYGROUND_DB;
CREATE OR REPLACE DATABASE $PLAYGROUND_DB COMMENT = 'Database for Docker Playground';
EOF
```

Create a Snowflake ROLE

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS $PLAYGROUND_CONNECTOR_ROLE;
CREATE ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE $PLAYGROUND_DB TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE $PLAYGROUND_DB TO ACCOUNTADMIN;
GRANT USAGE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA $PLAYGROUND_DB.PUBLIC TO $PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE ACCOUNTADMIN;
GRANT CREATE TABLE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT CREATE PIPE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
EOF
```

Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SYSADMIN;
CREATE OR REPLACE WAREHOUSE $PLAYGROUND_WAREHOUSE
  WAREHOUSE_SIZE = 'XSMALL'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 1
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for Kafka Playground';
GRANT USAGE ON WAREHOUSE $PLAYGROUND_WAREHOUSE TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
EOF
```

Create a Snowflake USER

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE USERADMIN;
DROP USER IF EXISTS $PLAYGROUND_USER;
CREATE USER $PLAYGROUND_USER
 PASSWORD = 'Password123!'
 LOGIN_NAME = $PLAYGROUND_USER
 DISPLAY_NAME = $PLAYGROUND_USER
 DEFAULT_WAREHOUSE = $PLAYGROUND_WAREHOUSE
 DEFAULT_ROLE = $PLAYGROUND_CONNECTOR_ROLE
 DEFAULT_NAMESPACE = $PLAYGROUND_DB
 MUST_CHANGE_PASSWORD = FALSE
 RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY";
USE ROLE SECURITYADMIN;
GRANT ROLE $PLAYGROUND_CONNECTOR_ROLE TO USER $PLAYGROUND_USER;
EOF
```

Create table `FOO`

```bash
$ docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
create or replace sequence seq1;
create or replace table FOO (id number default seq1.nextval, f1 string, update_ts timestamp default current_timestamp());
insert into FOO (f1) values ('value1');
insert into FOO (f1) values ('value2');
insert into FOO (f1) values ('value3');
EOF
```

Creating JDBC Snowflake Source connector

```bash
$ CONNECTION_URL="jdbc:snowflake://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com/?warehouse=$PLAYGROUND_WAREHOUSE&db=$PLAYGROUND_DB&role=$PLAYGROUND_CONNECTOR_ROLE&schema=PUBLIC&user=$PLAYGROUND_USER&private_key_file=/tmp/snowflake_key.p8&private_key_file_pwd=confluent&tracing=ALL"
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "$CONNECTION_URL",
               "table.whitelist": "FOO",
               "mode": "timestamp+incrementing",
               "timestamp.column.name": "UPDATE_TS",
               "incrementing.column.name": "ID",
               "topic.prefix": "snowflake-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/jdbc-snowflake-source/config | jq .
```

Verifying topic `snowflake-FOO`

```bash
playground topic consume --topic snowflake-FOO --min-expected-messages 3 --timeout 60
```


Results:

```json
{"ID":{"long":1},"F1":{"string":"value1"},"UPDATE_TS":{"long":1622527702201}}
{"ID":{"long":2},"F1":{"string":"value2"},"UPDATE_TS":{"long":1622527703388}}
{"ID":{"long":3},"F1":{"string":"value3"},"UPDATE_TS":{"long":1622527704663}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
