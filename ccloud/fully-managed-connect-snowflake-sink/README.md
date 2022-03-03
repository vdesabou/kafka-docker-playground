# Fully Managed  Snowflake Sink connector

## Objective

Quickly test [Snowflake Sink](https://docs.confluent.io/cloud/current/connectors/cc-snowflake-sink.html#) connector.

## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```

## How to run

Simply run:

```bash
$ ./fully-managed-snowflake-sink.sh <SNOWFLAKE_ACCOUNT_NAME> <SNOWFLAKE_USERNAME> <SNOWFLAKE_PASSWORD>
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
  SCALING_POLICY = 'STANDARD'
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

Sending messages to topic `test_table`

```bash
docker run --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}  kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

```

Creating Snowflake Sink connector

```bash
cat << EOF > connector.json
{
     "connector.class": "SnowflakeSink",
     "name": "SnowflakeSink",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "input.data.format": "AVRO",
     "topics": "test_table",
     "snowflake.url.name": "$SNOWFLAKE_URL",
     "snowflake.user.name": "$PLAYGROUND_USER",
     "snowflake.user.role": "$PLAYGROUND_CONNECTOR_ROLE",
     "snowflake.private.key":"$RSA_PRIVATE_KEY",
     "snowflake.private.key.passphrase": "confluent",
     "snowflake.database.name": "$PLAYGROUND_DB",
     "snowflake.schema.name":"PUBLIC",
     "tasks.max" : "1"
}
EOF

create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300
```

Confirm that the messages were delivered to the Snowflake table (logged as `KAFKA_DEMO` user)

```bash
$ docker run --rm -i -e SNOWSQL_PWD='Password123!' -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $PLAYGROUND_USER -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
SELECT * FROM $PLAYGROUND_DB.PUBLIC.TEST_TABLE;
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
