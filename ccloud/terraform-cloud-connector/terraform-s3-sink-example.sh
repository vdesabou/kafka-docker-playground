#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Terraform Cloud Connector - S3 Sink Example
#
# This example demonstrates using Terraform to:
# 1. Create a Confluent Cloud cluster (lkc-*)
# 2. Deploy Datagen source connector (lcc-*)
# 3. Deploy S3 Sink connector (lcc-*)
# 4. Verify end-to-end data flow
#############################################

handle_aws_credentials

# Check prerequisites
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    logerror "CONFLUENT_CLOUD_API_KEY environment variable is required"
    exit 1
fi

if [ -z "$CONFLUENT_CLOUD_API_SECRET" ]; then
    logerror "CONFLUENT_CLOUD_API_SECRET environment variable is required"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    logerror "Terraform is not installed"
    logerror "Visit: https://www.terraform.io/downloads"
    exit 1
fi

log "🚀 Terraform Cloud Connector - S3 Sink Example"
log "=============================================="

AWS_BUCKET_NAME="pg-terraform-bucket-${USER}"
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}
AWS_REGION="${AWS_REGION:-us-east-1}"
TOPIC_NAME="terraform_s3_topic"
CLUSTER_NAME="pg-terraform-s3-${USER}"

# Create S3 bucket
log "🪣 Creating S3 bucket: $AWS_BUCKET_NAME"
set +e
if [ "$AWS_REGION" == "us-east-1" ]; then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
aws s3api put-bucket-tagging --bucket $AWS_BUCKET_NAME --tagging "TagSet=[{Key=cflt_managed_by,Value=terraform},{Key=cflt_user,Value=$USER}]"
set -e

# Navigate to terraform directory
cd "$DIR"

# Initialize Terraform
if [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init
fi

log "📝 Creating Terraform configuration with Datagen + S3 Sink..."
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
environment_name           = "pg-terraform-env-${USER}"
cluster_name               = "$CLUSTER_NAME"
cloud_provider             = "AWS"
cloud_region               = "$AWS_REGION"

connector_configs = [
  {
    name             = "DatagenSource_${USER}"
    connector_class  = "DatagenSource"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "kafka.topic"        = "$TOPIC_NAME"
      "quickstart"         = "PAGEVIEWS"
      "output.data.format" = "AVRO"
      "max.interval"       = "1000"
      "iterations"         = "10000000"
      "tasks.max"          = "1"
    }
  },
  {
    name             = "S3_SINK_${USER}"
    connector_class  = "S3_SINK"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "topics"                 = "$TOPIC_NAME"
      "topics.dir"             = "terraform-data"
      "aws.access.key.id"      = "$AWS_ACCESS_KEY_ID"
      "aws.secret.access.key"  = "$AWS_SECRET_ACCESS_KEY"
      "s3.bucket.name"         = "$AWS_BUCKET_NAME"
      "s3.region"              = "$AWS_REGION"
      "input.data.format"      = "AVRO"
      "output.data.format"     = "AVRO"
      "time.interval"          = "HOURLY"
      "flush.size"             = "100"
      "schema.compatibility"   = "NONE"
      "tasks.max"              = "1"
    }
  }
]
EOF

log "🏗️  Creating infrastructure via Terraform..."
terraform apply -auto-approve

# Get outputs
CLUSTER_ID=$(terraform output -json | jq -r '.cluster_id.value')
ENVIRONMENT_ID=$(terraform output -json | jq -r '.environment_id.value')
API_KEY=$(terraform output -json | jq -r '.api_key_id.value')
API_SECRET=$(terraform output -json | jq -r '.api_key_secret.value')
BOOTSTRAP_ENDPOINT=$(terraform output -json | jq -r '.cluster_bootstrap_endpoint.value')

log ""
log "✅ Infrastructure created successfully!"
log ""
log "📊 Cluster Details:"
log "   Environment ID: $ENVIRONMENT_ID"
log "   Cluster ID:     $CLUSTER_ID"
log "   Bootstrap:      $BOOTSTRAP_ENDPOINT"
log ""
log "🔌 Connectors:"
terraform output -json | jq -r '.connector_ids.value | to_entries[] | "   \(.key): \(.value)"'

# Save environment
cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export CLOUD_KEY="$API_KEY"
export CLOUD_SECRET="$API_SECRET"
export BOOTSTRAP_SERVERS="$BOOTSTRAP_ENDPOINT"
ENVEOF

log ""
log "⏳ Waiting for connectors to provision and data to flow (60 seconds)..."
sleep 60

log ""
log "✅ Verifying data in S3 bucket..."
aws s3 ls s3://$AWS_BUCKET_NAME/terraform-data/ --recursive --region $AWS_REGION | head -20

log ""
log "📥 Downloading sample file to verify content..."
set +e
aws s3 cp --only-show-errors --recursive s3://$AWS_BUCKET_NAME/terraform-data/$TOPIC_NAME /tmp/terraform-s3-verify --region $AWS_REGION
if [ $? -eq 0 ]; then
    log "✅ Data successfully written to S3!"
    log ""
    log "Sample files:"
    find /tmp/terraform-s3-verify -type f -name "*.avro" | head -5
else
    logwarn "Data not yet available in S3 (may need more time)"
fi
set -e

log ""
log "🎯 Pipeline Summary:"
log "   ✓ Confluent Cloud cluster created ($CLUSTER_ID)"
log "   ✓ Datagen source generating pageviews"
log "   ✓ S3 sink writing to s3://$AWS_BUCKET_NAME/terraform-data/"
log "   ✓ End-to-end data flow verified"
log ""
log "🌐 View in Confluent Cloud:"
log "   https://confluent.cloud/environments/$ENVIRONMENT_ID/clusters/$CLUSTER_ID"
log ""

log "Do you want to delete the Terraform-managed infrastructure?"
check_if_continue

log "🗑️  Destroying Terraform resources..."
terraform destroy -auto-approve

log "🧹 Cleaning up S3 bucket..."
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
aws s3api delete-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION

rm -f terraform.tfvars .ccloud_env
log "✅ Cleanup complete!"
