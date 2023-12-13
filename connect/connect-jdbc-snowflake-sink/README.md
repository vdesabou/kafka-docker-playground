# JDBC Snowflake Sink connector


## Objective

Quickly test [JDBC Snowflake Sink](https://docs.confluent.io/kafka-connect-jdbc/current/sink-connector/index.html#jdbc-sink-connector-for-cp) connector.


## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

## How to run

Simply run:

```bash
$ playground run -f jdbc-snowflake-sink<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*> <SNOWFLAKE_ACCOUNT_NAME> <SNOWFLAKE_USERNAME> <SNOWFLAKE_PASSWORD>
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
create or replace table FOO (f1 string, update_ts timestamp default current_timestamp());
EOF
```

Sending messages to topic `FOO`

```bash
$ playground topic produce -t FOO --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF
```

Creating JDBC Snowflake Sink connector

```bash
$ CONNECTION_URL="jdbc:snowflake://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com/?warehouse=$PLAYGROUND_WAREHOUSE&db=$PLAYGROUND_DB&role=$PLAYGROUND_CONNECTOR_ROLE&schema=PUBLIC&user=$PLAYGROUND_USER&private_key_file=/tmp/snowflake_key.p8&private_key_file_pwd=confluent&tracing=ALL"
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "$CONNECTION_URL",
               "topics": "FOO",
               "auto.create": "false",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/jdbc-snowflake-sink/config | jq .
```

Confirm that the messages were delivered to the Snowflake table (logged as `$PLAYGROUND_USER` user)

```bash
$ docker run --rm -i -e SNOWSQL_PWD='Password123!' -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $PLAYGROUND_USER -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
SELECT * FROM $PLAYGROUND_DB.PUBLIC.FOO;
EOF
```

Results:

```
+---------+-------------------------+
| F1      | UPDATE_TS               |
|---------+-------------------------|
| value1  | 2021-06-01 06:39:46.229 |
| value10 | 2021-06-01 06:39:46.229 |
| value9  | 2021-06-01 06:39:46.229 |
| value8  | 2021-06-01 06:39:46.229 |
| value7  | 2021-06-01 06:39:46.229 |
| value6  | 2021-06-01 06:39:46.229 |
| value5  | 2021-06-01 06:39:46.229 |
| value4  | 2021-06-01 06:39:46.229 |
| value3  | 2021-06-01 06:39:46.229 |
| value2  | 2021-06-01 06:39:46.229 |
+---------+-------------------------+
10 Row(s) produced. Time Elapsed: 0.817s
Goodbye!
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
