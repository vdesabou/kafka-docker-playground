#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

SNOWFLAKE_ACCOUNT_NAME=${SNOWFLAKE_ACCOUNT_NAME:-$1}
SNOWFLAKE_USERNAME=${SNOWFLAKE_USERNAME:-$2}
SNOWFLAKE_PASSWORD=${SNOWFLAKE_PASSWORD:-$3}

if [ -z "$SNOWFLAKE_ACCOUNT_NAME" ]
then
     logerror "SNOWFLAKE_ACCOUNT_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SNOWFLAKE_USERNAME" ]
then
     logerror "SNOWFLAKE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SNOWFLAKE_PASSWORD" ]
then
     logerror "SNOWFLAKE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# https://<account_name>.<region_id>.snowflakecomputing.com:443
SNOWFLAKE_URL="https://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com"

# Create encrypted Private key - keep this safe, do not share!
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes256 -inform PEM -out snowflake_key.p8 -passout pass:confluent
# Generate public key from private key. You can share your public key.
openssl rsa -in snowflake_key.p8  -pubout -out snowflake_key.pub -passin pass:confluent


RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')


log "Create a Snowflake DB"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS KAFKA_DB;
CREATE OR REPLACE DATABASE KAFKA_DB COMMENT = 'Database for KafkaConnect demo';
EOF

log "Create a Snowflake ROLE"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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

log "Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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

log "Create a Snowflake USER"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

log "Creating Snowflake Sink connector"
docker exec -e SNOWFLAKE_URL="$SNOWFLAKE_URL" -e RSA_PRIVATE_KEY="$RSA_PRIVATE_KEY" connect \
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
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "transforms": "tombstoneHandlerExample",
               "transforms.tombstoneHandlerExample.type": "io.confluent.connect.transforms.TombstoneHandler"
          }' \
     http://localhost:8083/connectors/snowflake-sink-smt/config | jq .


sleep 5


log "Confirm that the messages were delivered to the Snowflake table (logged as KAFKA_DEMO user)"
docker run --rm -i -v $PWD/snowflake_key.p8:/tmp/rsa_key.p8 -e SNOWSQL_PRIVATE_KEY_PASSPHRASE=confluent snowsql:latest --username KAFKA_DEMO -a $SNOWFLAKE_ACCOUNT_NAME --private-key-path /tmp/rsa_key.p8 << EOF
USE ROLE KAFKA_CONNECTOR_ROLE;
USE DATABASE KAFKA_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE KAFKA_ADMIN_WAREHOUSE;
SELECT * FROM KAFKA_DB.PUBLIC.TEST_TABLE;
EOF