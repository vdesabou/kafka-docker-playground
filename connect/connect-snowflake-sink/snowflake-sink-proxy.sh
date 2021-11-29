#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

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

# Create encrypted Private key - keep this safe, do not share!
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes256 -inform PEM -out snowflake_key.p8 -passout pass:confluent
# Generate public key from private key. You can share your public key.
openssl rsa -in snowflake_key.p8  -pubout -out snowflake_key.pub -passin pass:confluent


RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')


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
  SCALING_POLICY = 'STANDARD'
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
EOF

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.proxy.yml"

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

log "Creating Snowflake Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
               "topics": "test_table",
               "tasks.max": "1",
               "snowflake.url.name": "'"$SNOWFLAKE_URL"'",
               "snowflake.user.name": "'"$PLAYGROUND_USER"'",
               "snowflake.user.role": "'"$PLAYGROUND_CONNECTOR_ROLE"'",
               "snowflake.private.key":"'"$RSA_PRIVATE_KEY"'",
               "snowflake.private.key.passphrase": "confluent",
               "snowflake.database.name": "'"$PLAYGROUND_DB"'",
               "jvm.proxy.host": "nginx-proxy",
               "jvm.proxy.port": "8888",
               "snowflake.schema.name":"PUBLIC",
               "buffer.count.records": "3",
               "buffer.flush.time" : "10",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/snowflake-sink-proxy/config | jq .

# [SF_KAFKA_CONNECTOR] enabling JDBC tracing (com.snowflake.kafka.connector.internal.SnowflakeURL:32)
# Nov 29, 2021 11:31:18 AM net.snowflake.client.jdbc.RestRequest execute
# SEVERE: Error response: HTTP Response code: 400, request: POST https://confluent_partner.snowflakecomputing.com:443/session/v1/login-request?databaseName=PLAYGROUNDDB700&schemaName=PUBLIC&requestId=209904c8-ae3c-4b71-aa4e-e62d3140bcf1 HTTP/1.1
# Nov 29, 2021 11:31:18 AM net.snowflake.client.core.HttpUtil executeRequestInternal
# SEVERE: Error executing request: POST https://confluent_partner.snowflakecomputing.com:443/session/v1/login-request?databaseName=PLAYGROUNDDB700&schemaName=PUBLIC&requestId=209904c8-ae3c-4b71-aa4e-e62d3140bcf1 HTTP/1.1
# Nov 29, 2021 11:31:18 AM net.snowflake.client.jdbc.SnowflakeUtil logResponseDetails
# SEVERE: Response status line reason: Bad Request
# Nov 29, 2021 11:31:18 AM net.snowflake.client.jdbc.SnowflakeUtil logResponseDetails
# SEVERE: Response content: <html>
# <head><title>400 Bad Request</title></head>
# <body>
# <center><h1>400 Bad Request</h1></center>
# <hr><center>nginx/1.18.0 (Ubuntu)</center>
# </body>
# </html>

# [2021-11-29 11:31:18,041] ERROR Validate: Error connecting to snowflake:
# [SF_KAFKA_CONNECTOR] Exception: Failed to connect to Snowflake Server
# [SF_KAFKA_CONNECTOR] Error Code: 1001
# [SF_KAFKA_CONNECTOR] Detail: Snowflake connection issue, reported by Snowflake JDBC
# [SF_KAFKA_CONNECTOR] Message: JDBC driver encountered communication error. Message: HTTP status=400.
# [SF_KAFKA_CONNECTOR] net.snowflake.client.core.HttpUtil.executeRequestInternal(HttpUtil.java:521)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.core.HttpUtil.executeRequest(HttpUtil.java:441)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.core.HttpUtil.executeGeneralRequest(HttpUtil.java:408)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.core.SessionUtil.newSession(SessionUtil.java:586)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.core.SessionUtil.openSession(SessionUtil.java:284)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.core.SFSession.open(SFSession.java:435)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.jdbc.DefaultSFConnectionHandler.initialize(DefaultSFConnectionHandler.java:104)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.jdbc.DefaultSFConnectionHandler.initializeConnection(DefaultSFConnectionHandler.java:79)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.jdbc.SnowflakeConnectionV1.initConnectionWithImpl(SnowflakeConnectionV1.java:116)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.jdbc.SnowflakeConnectionV1.<init>(SnowflakeConnectionV1.java:96)
# [SF_KAFKA_CONNECTOR] net.snowflake.client.jdbc.SnowflakeDriver.connect(SnowflakeDriver.java:164)
# [SF_KAFKA_CONNECTOR] com.snowflake.kafka.connector.internal.SnowflakeConnectionServiceV1.<init>(SnowflakeConnectionServiceV1.java:66)
# [SF_KAFKA_CONNECTOR] com.snowflake.kafka.connector.internal.SnowflakeConnectionServiceFactory$SnowflakeConnectionServiceBuilder.build(SnowflakeConnectionServiceFactory.java:75)
# [SF_KAFKA_CONNECTOR] com.snowflake.kafka.connector.SnowflakeSinkConnector.validate(SnowflakeSinkConnector.java:234)
# [SF_KAFKA_CONNECTOR] org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:465)
# [SF_KAFKA_CONNECTOR] org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$2(AbstractHerder.java:365)
# [SF_KAFKA_CONNECTOR] java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# [SF_KAFKA_CONNECTOR] java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# [SF_KAFKA_CONNECTOR] java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# [SF_KAFKA_CONNECTOR] java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# [SF_KAFKA_CONNECTOR] java.base/java.lang.Thread.run(Thread.java:829), errorCode:1001 (com.snowflake.kafka.connector.SnowflakeSinkConnector:236)
# [2021-11-29 11:31:18,042] INFO AbstractConfig values: 
#  (org.apache.kafka.common.config.AbstractConfig:376)


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
grep "scissors" /tmp/result.log

# docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-snowflake-sink --describe

# docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-snowflake-sink --to-earliest --topic test_table --reset-offsets --dry-run
# docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-snowflake-sink --to-earliest --topic test_table --reset-offsets --execute