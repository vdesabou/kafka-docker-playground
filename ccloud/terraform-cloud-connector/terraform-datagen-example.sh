#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Terraform Cloud Connector - Datagen Example
#
# This example demonstrates using Terraform to:
# 1. Create a Confluent Cloud cluster (lkc-*)
# 2. Deploy a Datagen connector (lcc-*)
# 3. Verify data generation
#############################################

# Check prerequisites
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    logerror "CONFLUENT_CLOUD_API_KEY environment variable is required"
    logerror "Get your Cloud API Key from https://confluent.cloud"
    exit 1
fi

if [ -z "$CONFLUENT_CLOUD_API_SECRET" ]; then
    logerror "CONFLUENT_CLOUD_API_SECRET environment variable is required"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    logerror "Terraform is not installed. Please install Terraform first."
    logerror "Visit: https://www.terraform.io/downloads"
    exit 1
fi

log "🚀 Terraform Cloud Connector - Datagen Example"
log "=============================================="

# Navigate to terraform directory
cd "$DIR"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init
fi

CLUSTER_NAME="pg-terraform-datagen-${USER}"
TOPIC_NAME="terraform_pageviews"

log "📝 Creating Terraform configuration..."
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
environment_name           = "pg-terraform-env-${USER}"
cluster_name               = "$CLUSTER_NAME"
cloud_provider             = "AWS"
cloud_region               = "${AWS_REGION:-us-east-1}"

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
  }
]
EOF

log "🏗️  Creating Confluent Cloud cluster and Datagen connector via Terraform..."
terraform apply -auto-approve

# Get outputs
CLUSTER_ID=$(terraform output -json | jq -r '.cluster_id.value')
ENVIRONMENT_ID=$(terraform output -json | jq -r '.environment_id.value')
CONNECTOR_ID=$(terraform output -json | jq -r '.connector_ids.value | to_entries[0].value // empty')
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

if [ -n "$CONNECTOR_ID" ]; then
    log ""
    log "🔌 Connector Details:"
    log "   Connector ID:   $CONNECTOR_ID"
    log "   Type:          DatagenSource"
    log "   Topic:         $TOPIC_NAME"
fi

# Save cluster info for playground use
log ""
log "💾 Saving cluster configuration..."
cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export CLOUD_KEY="$API_KEY"
export CLOUD_SECRET="$API_SECRET"
export BOOTSTRAP_SERVERS="$BOOTSTRAP_ENDPOINT"
ENVEOF

# Source the environment for playground commands
source .ccloud_env

log ""
log "⏳ Waiting for connector to be provisioned (30 seconds)..."
sleep 30

# Verify connector status using playground command
log "🔍 Checking connector status..."
set +e
playground connector status --connector "DatagenSource_${USER}" 2>/dev/null
CONNECTOR_STATUS=$?
set -e

if [ $CONNECTOR_STATUS -eq 0 ]; then
    log "✅ Connector is running"
else
    logwarn "Could not verify connector status with playground command"
    log "   You can check manually at: https://confluent.cloud"
fi

log ""
log "📈 Verifying data generation..."
log "   Topic: $TOPIC_NAME"

# Try to consume messages to verify
set +e
timeout 60 playground topic consume --topic "$TOPIC_NAME" --min-expected-messages 5 --timeout 60 2>/dev/null
CONSUME_STATUS=$?
set -e

if [ $CONSUME_STATUS -eq 0 ]; then
    log "✅ Successfully verified data generation!"
else
    log "⏩ Skipping message consumption verification"
    log "   (Cluster may still be initializing)"
fi

log ""
log "🎯 Next Steps:"
log ""
log "1. View cluster in Confluent Cloud:"
log "   https://confluent.cloud/environments/$ENVIRONMENT_ID/clusters/$CLUSTER_ID"
log ""
log "2. Use with playground commands:"
log "   source $DIR/.ccloud_env"
log "   playground topic list"
log "   playground connector list"
log ""
log "3. Monitor connector:"
log "   Connector ID: $CONNECTOR_ID"
log ""
log "4. View Terraform outputs:"
log "   cd $DIR && terraform output"
log ""

log "Do you want to delete the Terraform-managed infrastructure?"
check_if_continue

log "🗑️  Destroying Terraform resources..."
terraform destroy -auto-approve
rm -f terraform.tfvars .ccloud_env

log "✅ Cleanup complete!"
