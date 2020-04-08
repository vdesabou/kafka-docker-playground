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

set +e
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SECURITYADMIN;
DROP USER kafka;
EOF
set -e

log "Setting up Snowflake account and key pair"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" snowsql:latest --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT SET TIMEZONE = 'Etc/UTC';
USE ROLE SECURITYADMIN;
ALTER SESSION SET TIMEZONE = 'Etc/UTC';
CREATE USER kafka RSA_PUBLIC_KEY='$RSA_PUBLIC_KEY';
GRANT ROLE SYSADMIN TO USER kafka;
EOF


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

# to avoid https://support.snowflake.net/s/article/ERROR-JWT-token-is-invalid
# docker exec connect apt-get update
# docker exec connect apt-get install -y ntpdate
# docker exec --privileged --user root -t connect bash -c "ntpdate 1.ro.pool.ntp.org"


log "Creating Snowflake Sink connector"
docker exec -e SNOWFLAKE_URL="$SNOWFLAKE_URL" -e SNOWFLAKE_USERNAME="$SNOWFLAKE_USERNAME" -e RSA_PRIVATE_KEY="$RSA_PRIVATE_KEY" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
               "topics": "test_table",
               "tasks.max": "1",
               "snowflake.url.name":"'"$SNOWFLAKE_URL"'",
               "snowflake.user.name":"'"$SNOWFLAKE_USERNAME"'",
               "snowflake.user.role":"SYSADMIN",
               "snowflake.private.key":"'"$RSA_PRIVATE_KEY"'",
               "snowflake.private.key.passphrase": "jkladu098jfd089adsq4r",
               "snowflake.database.name":"DEMO_DB",
               "snowflake.schema.name":"PUBLIC",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "com.snowflake.kafka.connector.records.SnowflakeAvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/snowflake-sink/config | jq .


sleep 5

log "Confirm that the messages were delivered to the Snowflake table"
