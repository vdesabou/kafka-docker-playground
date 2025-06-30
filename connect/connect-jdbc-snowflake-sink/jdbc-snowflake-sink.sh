#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

username=$(whoami)
uppercase_username=$(echo $username | tr '[:lower:]' '[:upper:]')

PLAYGROUND_DB=PG_DB_${uppercase_username}${TAG}
PLAYGROUND_DB=${PLAYGROUND_DB//[-._]/}

PLAYGROUND_WAREHOUSE=PG_WH_${uppercase_username}${TAG}
PLAYGROUND_WAREHOUSE=${PLAYGROUND_WAREHOUSE//[-._]/}

PLAYGROUND_CONNECTOR_ROLE=PG_ROLE_${uppercase_username}${TAG}
PLAYGROUND_CONNECTOR_ROLE=${PLAYGROUND_CONNECTOR_ROLE//[-._]/}

PLAYGROUND_USER=PG_USER_${uppercase_username}${TAG}
PLAYGROUND_USER=${PLAYGROUND_USER//[-._]/}

cd ../../connect/connect-jdbc-snowflake-sink
if [ ! -f ${PWD}/snowflake-jdbc-3.13.16.jar ]
then
     # newest versions do not work well with timestamp date, getting:
     # WARN JDBC type 2014 (TIMESTAMPIZ) not currently supported
     log "Downloading snowflake-jdbc-3.13.16.jar"
     wget -q https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.13.16/snowflake-jdbc-3.13.16.jar
fi
cd -

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

cd ../../connect/connect-jdbc-snowflake-sink
# using v1 PBE-SHA1-RC4-128, see https://community.snowflake.com/s/article/Private-key-provided-is-invalid-or-not-supported-rsa-key-p8--data-isn-t-an-object-ID
# Create encrypted Private key - keep this safe, do not share!
docker run -u0 --rm -v $PWD:/tmp vulhub/openssl:1.0.1c bash -c "openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -v1 PBE-SHA1-RC4-128 -out /tmp/snowflake_key.p8 -passout pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
# Generate public key from private key. You can share your public key.
docker run -u0 --rm -v $PWD:/tmp vulhub/openssl:1.0.1c bash -c "openssl rsa -in /tmp/snowflake_key.p8 -pubout -out /tmp/snowflake_key.pub -passin pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"

RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')
cd -

if [ -z "$GITHUB_RUN_NUMBER" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod a+rw snowflake_key.p8
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod a+rw snowflake_key.p8
    ls -lrt
fi

log "Create a Snowflake DB"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS $PLAYGROUND_DB;
CREATE OR REPLACE DATABASE $PLAYGROUND_DB COMMENT = 'Database for Docker Playground';
EOF

log "Create a Snowflake ROLE"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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
GRANT ROLE $PLAYGROUND_CONNECTOR_ROLE TO ROLE ACCOUNTADMIN;
EOF

log "Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create table foo"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
create or replace table FOO (f1 string, update_ts timestamp default current_timestamp());
EOF

log "Sending messages to topic FOO"
playground topic produce -t FOO --nb-messages 10 --forced-value '{"F1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "F1",
      "type": "string"
    }
  ]
}
EOF

# https://docs.snowflake.com/en/user-guide/jdbc-configure.html#jdbc-driver-connection-string
CONNECTION_URL="jdbc:snowflake://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com/?warehouse=$PLAYGROUND_WAREHOUSE&db=$PLAYGROUND_DB&role=$PLAYGROUND_CONNECTOR_ROLE&schema=PUBLIC&user=$PLAYGROUND_USER&private_key_file=/tmp/snowflake_key.p8&private_key_file_pwd=confluent&tracing=ALL"
log "Creating JDBC Snowflake Sink connector"
playground connector create-or-update --connector jdbc-snowflake-sink  << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
     "tasks.max": "1",
     "connection.url": "$CONNECTION_URL",
     "topics": "FOO",
     "auto.create": "false",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF


sleep 30

log "Confirm that the messages were delivered to the Snowflake table (logged as $PLAYGROUND_USER user)"
docker run --quiet --rm -i -e SNOWSQL_PWD='Password123!' -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $PLAYGROUND_USER -a $SNOWFLAKE_ACCOUNT_NAME > /tmp/result.log  2>&1 <<-EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
SELECT * FROM $PLAYGROUND_DB.PUBLIC.FOO;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
