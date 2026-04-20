#!/bin/bash
set -e

#############################################
# Complete Pipeline Example
#
# This example demonstrates:
# 1. Creating a Confluent Cloud cluster
# 2. Deploying a Datagen source connector
# 3. Deploying an S3 sink connector
# 4. Verifying data flow
#############################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PARENT_DIR="$(dirname "$DIR")"

# Source utilities
source ${PARENT_DIR}/../../scripts/utils.sh

log "🚀 Complete Terraform Pipeline Example"
log "======================================="

# Check prerequisites
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    logerror "CONFLUENT_CLOUD_API_KEY is not set"
    exit 1
fi

if [ -z "$CONFLUENT_CLOUD_API_SECRET" ]; then
    logerror "CONFLUENT_CLOUD_API_SECRET is not set"
    exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    logerror "AWS_ACCESS_KEY_ID is not set"
    exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    logerror "AWS_SECRET_ACCESS_KEY is not set"
    exit 1
fi

# Configuration
AWS_BUCKET_NAME="pg-terraform-bucket-${USER}"
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}
AWS_REGION="${AWS_REGION:-us-east-1}"
TOPIC_NAME="terraform_pageviews"

log "📋 Configuration:"
log "   Bucket: $AWS_BUCKET_NAME"
log "   Region: $AWS_REGION"
log "   Topic: $TOPIC_NAME"
log ""

# Step 1: Create S3 bucket
log "🪣 Step 1: Creating S3 bucket..."
set +e
if [ "$AWS_REGION" == "us-east-1" ]; then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
aws s3api put-bucket-tagging --bucket $AWS_BUCKET_NAME --tagging "TagSet=[{Key=cflt_managed_by,Value=terraform},{Key=cflt_user,Value=$USER}]"
set -e

# Step 2: Create Datagen connector config
log "📝 Step 2: Creating Datagen connector configuration..."
cat > /tmp/datagen-config.json << EOF
{
  "kafka.topic": "$TOPIC_NAME",
  "quickstart": "PAGEVIEWS",
  "output.data.format": "AVRO",
  "tasks.max": "1",
  "max.interval": "1000",
  "iterations": "10000"
}
EOF

# Step 3: Deploy cluster with Datagen connector
log "🏗️  Step 3: Deploying Confluent Cloud cluster with Datagen connector..."
cd "$PARENT_DIR"
./terraform-cloud-connector.sh --apply \
    --connector-type DATAGEN \
    --connector-config /tmp/datagen-config.json \
    --cloud AWS \
    --region $AWS_REGION

# Step 4: Wait for data generation
log "⏳ Step 4: Waiting for data generation (30 seconds)..."
sleep 30

# Step 5: Add S3 Sink connector using Terraform
log "🔌 Step 5: Adding S3 Sink connector..."

# Update terraform.tfvars to add S3 sink
cat >> terraform.tfvars << EOF

# S3 Sink Connector
connector_configs = [
  {
    name             = "DATAGEN_\${USER}"
    connector_class  = "DATAGEN"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "kafka.topic"        = "$TOPIC_NAME"
      "quickstart"         = "PAGEVIEWS"
      "output.data.format" = "AVRO"
      "tasks.max"          = "1"
      "max.interval"       = "1000"
      "iterations"         = "10000"
    }
  },
  {
    name             = "S3_SINK_\${USER}"
    connector_class  = "S3_SINK"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "topics"               = "$TOPIC_NAME"
      "topics.dir"           = "terraform-data"
      "aws.access.key.id"    = "$AWS_ACCESS_KEY_ID"
      "aws.secret.access.key" = "$AWS_SECRET_ACCESS_KEY"
      "s3.bucket.name"       = "$AWS_BUCKET_NAME"
      "s3.region"            = "$AWS_REGION"
      "input.data.format"    = "AVRO"
      "output.data.format"   = "AVRO"
      "time.interval"        = "HOURLY"
      "flush.size"           = "100"
      "schema.compatibility" = "NONE"
      "tasks.max"            = "1"
    }
  }
]
EOF

terraform apply -auto-approve

# Step 6: Wait for data to flow to S3
log "⏳ Step 6: Waiting for data to be written to S3 (60 seconds)..."
sleep 60

# Step 7: Verify data in S3
log "✅ Step 7: Verifying data in S3..."
aws s3 ls s3://$AWS_BUCKET_NAME/terraform-data/ --recursive --region $AWS_REGION | head -20

log ""
log "🎉 Pipeline deployment complete!"
log ""
log "📊 Summary:"
log "   ✓ Confluent Cloud cluster created"
log "   ✓ Datagen source connector generating data"
log "   ✓ S3 sink connector writing to bucket"
log "   ✓ Data verified in S3"
log ""
log "🧹 To clean up resources:"
log "   cd $PARENT_DIR && ./stop.sh"
log ""
log "📚 To view connector details:"
log "   source .ccloud_env"
log "   playground connector list"
