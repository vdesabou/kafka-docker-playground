#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



username=$(whoami)
uppercase_username=$(echo $username | tr '[:lower:]' '[:upper:]')

PLAYGROUND_DB=PG_DB_${uppercase_username}${TAG}_streaming
PLAYGROUND_DB=${PLAYGROUND_DB//[-._]/}

PLAYGROUND_WAREHOUSE=PG_WH_${uppercase_username}${TAG}_streaming
PLAYGROUND_WAREHOUSE=${PLAYGROUND_WAREHOUSE//[-._]/}

PLAYGROUND_CONNECTOR_ROLE=PG_ROLE_${uppercase_username}${TAG}_streaming
PLAYGROUND_CONNECTOR_ROLE=${PLAYGROUND_CONNECTOR_ROLE//[-._]/}

PLAYGROUND_USER=PG_USER_${uppercase_username}${TAG}_streaming
PLAYGROUND_USER=${PLAYGROUND_USER//[-._]/}

SNOWFLAKE_ACCOUNT_NAME=${SNOWFLAKE_ACCOUNT_NAME:-$1}
SNOWFLAKE_USERNAME=${SNOWFLAKE_USERNAME:-$2}
SNOWFLAKE_PASSWORD=${SNOWFLAKE_PASSWORD:-$3}

# AWS S3 configuration for Iceberg storage
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-$4}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-$5}

# Try to read AWS credentials from environment or AWS config files
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
     handle_aws_credentials
fi

# Extract AWS account ID if AWS credentials are available
# Can be overridden with AWS_ACCOUNT_ID environment variable
if [ -z "$AWS_ACCOUNT_ID" ]; then
     if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]; then
          AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
          log "Extracted AWS Account ID: $AWS_ACCOUNT_ID"
     fi
fi

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

logwarn "This example requires Snowflake to be Enterprise Edition for iceberg to work, if you are using trial account, please make sure to select Enterprise Edition when you sign up"

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]
then
     logerror "AWS credentials are required for Iceberg storage. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic test_table
set -e

# https://<account_name>.<region_id>.snowflakecomputing.com:443
SNOWFLAKE_URL="https://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com"

# Fully managed connectors use <locator>.<region>.<cloud> format (e.g. abc123.us-east-1.aws)
# SnowSQL expects <locator>.<region> without the cloud suffix
SNOWSQL_ACCOUNT_NAME=$(echo "$SNOWFLAKE_ACCOUNT_NAME" | sed 's/\.\(aws\|azure\|gcp\)$//')

S3_BUCKET_NAME=${S3_BUCKET_NAME:-playground-iceberg-${username}}

# Get Snowflake AWS account ID dynamically by querying DESC STORAGE INTEGRATION
log "Fetching Snowflake AWS account ID..."
STORAGE_AWS_IAM_USER_ARN=$(docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << 'EOF' 2>/dev/null | grep -oE 'arn:aws:iam::[0-9]{12}:user/[^ ]*' | head -1
CREATE STORAGE INTEGRATION temp_get_iam
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::000000000000:role/dummy'
  STORAGE_ALLOWED_LOCATIONS = ('s3://dummy/');
DESC STORAGE INTEGRATION temp_get_iam;
DROP STORAGE INTEGRATION temp_get_iam;
EOF
)

SNOWFLAKE_AWS_ACCOUNT=$(echo "$STORAGE_AWS_IAM_USER_ARN" | grep -oE '[0-9]{12}' | head -1)

if [ -z "$SNOWFLAKE_AWS_ACCOUNT" ]; then
     logerror "❌ Could not extract Snowflake AWS account ID from: $STORAGE_AWS_IAM_USER_ARN"
     logerror "Please set manually: export SNOWFLAKE_AWS_ACCOUNT=<your_12_digit_account_id>"
     exit 1
fi

log "✅ Snowflake AWS IAM User ARN: $STORAGE_AWS_IAM_USER_ARN"
log "✅ Snowflake AWS Account ID: $SNOWFLAKE_AWS_ACCOUNT"

log "Creating S3 bucket for Iceberg storage: $S3_BUCKET_NAME in region $AWS_REGION"
set +e
if [ "$AWS_REGION" = "us-east-1" ]; then
     aws s3api create-bucket \
          --bucket "$S3_BUCKET_NAME" \
          --region "$AWS_REGION"
else
     aws s3api create-bucket \
          --bucket "$S3_BUCKET_NAME" \
          --region "$AWS_REGION" \
          --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi
BUCKET_RESULT=$?
set -e

if [ $BUCKET_RESULT -eq 0 ]; then
     log "✅ S3 bucket created successfully"
else
     log "⚠️ S3 bucket creation returned code $BUCKET_RESULT (assuming it already exists)"
fi

log "Verifying S3 bucket accessibility..."
set +e
aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>&1 | tee /tmp/bucket_check.log
BUCKET_CHECK=$?
set -e

if [ $BUCKET_CHECK -ne 0 ]; then
     logerror "❌ S3 bucket '$S3_BUCKET_NAME' does not exist or is not accessible"
     cat /tmp/bucket_check.log
     exit 1
fi
log "✅ S3 bucket is accessible"

set +e
aws s3api put-bucket-versioning \
     --bucket "$S3_BUCKET_NAME" \
     --versioning-configuration Status=Enabled
set -e

set +e
aws s3api put-bucket-encryption \
     --bucket "$S3_BUCKET_NAME" \
     --server-side-encryption-configuration '{
          "Rules": [
               {
                    "ApplyServerSideEncryptionByDefault": {
                         "SSEAlgorithm": "AES256"
                    }
               }
          ]
     }'
set -e
log "S3 bucket versioning and encryption configured"

log "Creating cross-account IAM role for Snowflake to access S3 bucket"
SNOWFLAKE_ROLE_NAME="snowflake-iceberg-role"

TRUST_POLICY='{
     "Version": "2012-10-17",
     "Statement": [
          {
               "Effect": "Allow",
               "Principal": {
                    "AWS": "'$STORAGE_AWS_IAM_USER_ARN'"
               },
               "Action": "sts:AssumeRole"
          }
     ]
}'

set +e
aws iam delete-role-policy --role-name "$SNOWFLAKE_ROLE_NAME" --policy-name "snowflake-s3-iceberg-policy" 2>/dev/null
aws iam delete-role --role-name "$SNOWFLAKE_ROLE_NAME" 2>/dev/null
set -e

aws iam create-role \
     --role-name "$SNOWFLAKE_ROLE_NAME" \
     --assume-role-policy-document "$TRUST_POLICY" \
     --description "Cross-account role for Snowflake Iceberg access to S3"
log "✅ Cross-account IAM role created: $SNOWFLAKE_ROLE_NAME"

S3_POLICY='{
     "Version": "2012-10-17",
     "Statement": [
          {
               "Effect": "Allow",
               "Action": [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:DeleteObject"
               ],
               "Resource": "arn:aws:s3:::'$S3_BUCKET_NAME'/*"
          },
          {
               "Effect": "Allow",
               "Action": [
                    "s3:ListBucket",
                    "s3:GetBucketVersioning",
                    "s3:ListBucketVersions"
               ],
               "Resource": "arn:aws:s3:::'$S3_BUCKET_NAME'"
          }
     ]
}'

set +e
aws iam delete-role-policy \
     --role-name "$SNOWFLAKE_ROLE_NAME" \
     --policy-name "snowflake-s3-iceberg-policy" 2>/dev/null
set -e

aws iam put-role-policy \
     --role-name "$SNOWFLAKE_ROLE_NAME" \
     --policy-name "snowflake-s3-iceberg-policy" \
     --policy-document "$S3_POLICY"
log "✅ S3 bucket access policy attached to role"

cd ../../ccloud/fm-snowflake-sink
# using v1 PBE-SHA1-RC4-128, see https://community.snowflake.com/s/article/Private-key-provided-is-invalid-or-not-supported-rsa-key-p8--data-isn-t-an-object-ID
# Create encrypted Private key - keep this safe, do not share!
docker run -u0 --rm -v $PWD:/tmp vulhub/openssl:1.0.1c bash -c "openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -v1 PBE-SHA1-RC4-128 -out /tmp/snowflake_key.p8 -passout pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
# Generate public key from private key. You can share your public key.
docker run -u0 --rm -v $PWD:/tmp vulhub/openssl:1.0.1c bash -c "openssl rsa -in /tmp/snowflake_key.p8 -pubout -out /tmp/snowflake_key.pub -passin pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"

RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')
cd -

log "Create a Snowflake DB"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS $PLAYGROUND_DB;
CREATE OR REPLACE DATABASE $PLAYGROUND_DB COMMENT = 'Database for Docker Playground';
EOF

log "Create a Snowflake ROLE"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << EOF
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
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << EOF
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
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << EOF
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

log "Grant Iceberg-specific permissions for the connector role"
docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << EOF
USE ROLE SECURITYADMIN;
GRANT CREATE ICEBERG TABLE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT MODIFY ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT ALL ON FUTURE ICEBERG TABLES IN SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
EOF

log "Creating Snowflake S3 storage integration, external volume and Iceberg table"
STORAGE_INTEGRATION_NAME="PG_S3_INTEGRATION_${uppercase_username}${TAG}"
STORAGE_INTEGRATION_NAME=${STORAGE_INTEGRATION_NAME//[-._]/}

docker run --quiet --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWSQL_ACCOUNT_NAME << EOF
USE ROLE ACCOUNTADMIN;

-- Create S3 Storage Integration for Iceberg
CREATE OR REPLACE STORAGE INTEGRATION $STORAGE_INTEGRATION_NAME
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::$AWS_ACCOUNT_ID:role/snowflake-iceberg-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://$S3_BUCKET_NAME/iceberg/');

GRANT USAGE ON INTEGRATION $STORAGE_INTEGRATION_NAME TO ROLE $PLAYGROUND_CONNECTOR_ROLE;

-- Create external volume with proper S3 configuration using cross-account role
CREATE OR REPLACE EXTERNAL VOLUME iceberg_volume
  STORAGE_LOCATIONS = (
    (
      NAME = 's3-location'
      STORAGE_PROVIDER = 'S3'
      STORAGE_BASE_URL = 's3://$S3_BUCKET_NAME/'
      STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::$AWS_ACCOUNT_ID:role/snowflake-iceberg-role'
    )
  );

-- Verify the external volume is accessible
SELECT SYSTEM\$VERIFY_EXTERNAL_VOLUME('iceberg_volume');

-- Grant the connector role permission to use the external volume
GRANT USAGE ON EXTERNAL VOLUME iceberg_volume TO ROLE $PLAYGROUND_CONNECTOR_ROLE;

-- Switch to the playground connector role to create the Iceberg table
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;

-- Drop the table if it exists (to ensure clean state)
DROP TABLE IF EXISTS TEST_TABLE;

-- Create the Iceberg table with record_metadata as base column
-- The connector will auto-evolve the schema based on incoming record schema
CREATE ICEBERG TABLE TEST_TABLE (
  record_metadata OBJECT()
)
EXTERNAL_VOLUME = 'iceberg_volume'
CATALOG = 'SNOWFLAKE'
BASE_LOCATION = 'iceberg/TEST_TABLE';

-- Enable schema evolution separately (required for connector schematization)
ALTER ICEBERG TABLE TEST_TABLE SET ENABLE_SCHEMA_EVOLUTION = TRUE;

SHOW ICEBERG TABLES LIKE 'TEST_TABLE';
EOF

log "S3 bucket configured: $S3_BUCKET_NAME"
log "AWS Account ID: $AWS_ACCOUNT_ID"
log "Note: Verify the IAM role ARN (arn:aws:iam::$AWS_ACCOUNT_ID:role/snowflake-iceberg-role) exists in your AWS account"

log "Creating test_table topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic test_table
set -e

log "Sending messages to topic test_table"
playground topic produce -t test_table --nb-messages 10 << 'EOF'
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

connector_name="SnowflakeIcebergSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector with Iceberg integration"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "SnowflakeSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "input.data.format": "AVRO",
  "topics": "test_table",
  "snowflake.url.name": "$SNOWFLAKE_URL",
  "snowflake.user.name": "$PLAYGROUND_USER",
  "snowflake.private.key": "$RSA_PRIVATE_KEY",
  "snowflake.private.key.passphrase": "confluent",
  "snowflake.database.name": "$PLAYGROUND_DB",
  "snowflake.schema.name": "PUBLIC",
  "snowflake.role.name": "$PLAYGROUND_CONNECTOR_ROLE",
  "snowflake.ingestion.method": "SNOWPIPE_STREAMING",
  "snowflake.enable.schematization": "true",
  "snowflake.streaming.iceberg.enabled": "true",
  "buffer.flush.time": "10",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground connector show-lag --max-wait 120 --connector $connector_name

log "Confirm that the messages were delivered to the Snowflake Iceberg table (logged as $PLAYGROUND_USER user)"
docker run --quiet --rm -i -e SNOWSQL_PWD='Password123!' -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $PLAYGROUND_USER -a $SNOWSQL_ACCOUNT_NAME > /tmp/result.log  2>&1 <<-EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
SELECT * FROM $PLAYGROUND_DB.PUBLIC.TEST_TABLE;
SHOW ICEBERG TABLES IN SCHEMA $PLAYGROUND_DB.PUBLIC;
EOF
cat /tmp/result.log
grep -i "u_name" /tmp/result.log

log "Validating Iceberg parquet files directly from S3..."
PARQUET_FILE=$(aws s3 ls s3://${S3_BUCKET_NAME}/ --recursive | grep "\.parquet" | head -1 | awk '{print $4}')
if [ ! -z "$PARQUET_FILE" ]
then
     log "Downloading parquet file: $PARQUET_FILE"
     aws s3 cp s3://${S3_BUCKET_NAME}/${PARQUET_FILE} /tmp/iceberg_validation.parquet
     log "Reading parquet file contents:"
     docker run --rm -v /tmp/iceberg_validation.parquet:/tmp/iceberg_validation.parquet python:3.11-slim bash -c "
          pip install pyarrow --quiet --no-warn-script-location 2>/dev/null
          python3 -c \"
import pyarrow.parquet as pq
table = pq.read_table('/tmp/iceberg_validation.parquet')
print('Schema:', [f.name for f in table.schema])
print()
print('Records:')
for i in range(table.num_rows):
    row = {col: table.column(col)[i].as_py() for col in table.schema.names}
    print(row)
\""
else
     logwarn "No parquet files found in S3 bucket yet"
fi

log "==========================================="
log "Snowflake Iceberg Setup Complete"
log "==========================================="
log "Snowflake Account: $SNOWFLAKE_ACCOUNT_NAME"
log "Database: $PLAYGROUND_DB"
log "Warehouse: $PLAYGROUND_WAREHOUSE"
log "Role: $PLAYGROUND_CONNECTOR_ROLE"
log "User: $PLAYGROUND_USER"
log "S3 Bucket for Iceberg Storage: $S3_BUCKET_NAME"
log "S3 Region: $AWS_REGION"
log "==========================================="

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
