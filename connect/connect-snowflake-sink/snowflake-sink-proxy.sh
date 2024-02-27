#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



PLAYGROUND_DB=PLAYGROUND_DB${TAG}
PLAYGROUND_DB=${PLAYGROUND_DB//[-._]/}

PLAYGROUND_WAREHOUSE=PLAYGROUND_WAREHOUSE${TAG}
PLAYGROUND_WAREHOUSE=${PLAYGROUND_WAREHOUSE//[-._]/}

PLAYGROUND_CONNECTOR_ROLE=PLAYGROUND_CONNECTOR_ROLE${TAG}
PLAYGROUND_CONNECTOR_ROLE=${PLAYGROUND_CONNECTOR_ROLE//[-._]/}

PLAYGROUND_USER=PLAYGROUND_USER${TAG}
PLAYGROUND_USER=${PLAYGROUND_USER//[-._]/}

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

cd ../../connect/connect-snowflake-sink
# using v1 PBE-SHA1-RC4-128, see https://community.snowflake.com/s/article/Private-key-provided-is-invalid-or-not-supported-rsa-key-p8--data-isn-t-an-object-ID
# Create encrypted Private key - keep this safe, do not share!
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -v1 PBE-SHA1-RC4-128 -out /tmp/snowflake_key.p8 -passout pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
# Generate public key from private key. You can share your public key.
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "openssl rsa -in /tmp/snowflake_key.p8 -pubout -out /tmp/snowflake_key.pub -passin pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"

RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')
cd -

# generate data file for externalizing secrets
sed -e "s|:RSA_PRIVATE_KEY:|$RSA_PRIVATE_KEY|g" \
    ../../connect/connect-snowflake-sink/data.template > ../../connect/connect-snowflake-sink/data

log "Create a Snowflake DB"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS $PLAYGROUND_DB;
CREATE OR REPLACE DATABASE $PLAYGROUND_DB COMMENT = 'Database for Docker Playground';
EOF

log "Create a Snowflake ROLE"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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

log "Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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

log "Create a Snowflake USER"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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
GRANT ROLE $PLAYGROUND_CONNECTOR_ROLE TO ACCOUNTADMIN;
EOF

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

log "Sending messages to topic test_table"
playground topic produce -t test_table --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "u_name",
      "type": "string"
    },
    {
      "name": "u_price",
      "type": "float"
    },
    {
      "name": "u_quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Creating Snowflake Sink connector"
playground connector create-or-update --connector snowflake-sink  << EOF
{
     "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
     "topics": "test_table",
     "tasks.max": "1",
     "snowflake.url.name": "$SNOWFLAKE_URL",
     "snowflake.user.name": "$PLAYGROUND_USER",
     
     "snowflake.private.key": "\${file:/data:private.key}",
     "snowflake.private.key.passphrase": "confluent",
     "snowflake.database.name": "$PLAYGROUND_DB",
     "jvm.proxy.host": "squid",
     "jvm.proxy.port": "3128",
     "snowflake.schema.name":"PUBLIC",
     "buffer.count.records": "3",
     "buffer.flush.time" : "10",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF


sleep 120

log "Confirm that the messages were delivered to the Snowflake table (logged as $PLAYGROUND_USER user)"
docker run --rm -i -e SNOWSQL_PWD='Password123!' -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $PLAYGROUND_USER -a $SNOWFLAKE_ACCOUNT_NAME > /tmp/result.log  2>&1 <<-EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
SELECT * FROM $PLAYGROUND_DB.PUBLIC.TEST_TABLE;
EOF
cat /tmp/result.log
grep "u_name" /tmp/result.log

# docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-snowflake-sink --describe

# docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-snowflake-sink --to-earliest --topic test_table --reset-offsets --dry-run
# docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-snowflake-sink --to-earliest --topic test_table --reset-offsets --execute