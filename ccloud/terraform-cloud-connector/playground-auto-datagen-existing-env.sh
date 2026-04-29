#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Playground Auto Datagen - Use Existing Environment
#
# Fully automated Datagen deployment using existing env
# No manual configuration needed!
#
# Usage: playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen-existing-env.sh
#############################################

log "🚀 Terraform Cloud Connector - Datagen (Existing Environment)"
log "=============================================================="
log ""

# Check credentials
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    if [ -f "$DIR/.env" ]; then
        source "$DIR/.env"
    else
        logerror "Please set CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET"
        exit 1
    fi
fi

log "✅ Credentials configured"

cd "$DIR"

# List available environments
log ""
log "📋 Available Environments:"
ENV_LIST=$(curl -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  "https://api.confluent.cloud/org/v2/environments" | jq -r '.data[] | "\(.id)|\(.display_name)"')

echo "$ENV_LIST" | while IFS='|' read -r id name; do
    log "   $id - $name"
done

# Auto-select first environment or prompt
FIRST_ENV=$(echo "$ENV_LIST" | head -1 | cut -d'|' -f1)
log ""
log "Using environment: $FIRST_ENV"
ENVIRONMENT_ID="$FIRST_ENV"

# Initialize Terraform
if [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init > /dev/null 2>&1
fi

# Generate configuration using existing environment
CLUSTER_NAME="pg-datagen-${USER}-$(date +%s)"
TOPIC_NAME="pageviews"

log ""
log "📝 Configuration:"
log "   Environment: $ENVIRONMENT_ID"
log "   Cluster: $CLUSTER_NAME"
log "   Topic: $TOPIC_NAME"
log "   Cloud: AWS"
log "   Region: us-east-1"

# Create terraform.tfvars
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
use_existing_environment   = true
environment_id             = "$ENVIRONMENT_ID"
cluster_name               = "$CLUSTER_NAME"
cloud_provider             = "AWS"
cloud_region               = "us-east-1"

connector_configs = [
  {
    name             = "DatagenSource_${USER}"
    connector_class  = "DatagenSource"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "kafka.topic"        = "$TOPIC_NAME"
      "quickstart"         = "PAGEVIEWS"
      "output.data.format" = "JSON"
      "tasks.max"          = "1"
    }
  }
]
EOF

log ""
log "🏗️  Deploying Confluent Cloud infrastructure..."
log "   (This takes 3-5 minutes)"

terraform apply -auto-approve

# Get outputs
CLUSTER_ID=$(terraform output -json 2>/dev/null | jq -r '.cluster_id.value // empty')
CONNECTOR_ID=$(terraform output -json 2>/dev/null | jq -r '.connector_ids.value | to_entries[0].value // empty')
API_KEY=$(terraform output -json 2>/dev/null | jq -r '.api_key_id.value // empty')
API_SECRET=$(terraform output -json 2>/dev/null | jq -r '.api_key_secret.value // empty')
BOOTSTRAP_ENDPOINT=$(terraform output -json 2>/dev/null | jq -r '.cluster_bootstrap_endpoint.value // empty')

log ""
log "╔════════════════════════════════════════════════════════╗"
log "║  Deployment Complete! 🎉                               ║"
log "╚════════════════════════════════════════════════════════╝"
log ""
log "📊 Cluster Details:"
log "   Environment ID: $ENVIRONMENT_ID"
log "   Cluster ID:     $CLUSTER_ID"
log "   Bootstrap:      $BOOTSTRAP_ENDPOINT"
log ""

if [ -n "$CONNECTOR_ID" ]; then
    log "🔌 Connector Details:"
    log "   Connector ID:   $CONNECTOR_ID"
    log "   Type:          DatagenSource"
    log "   Topic:         $TOPIC_NAME"
    log ""
fi

# Save environment
cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export CLOUD_KEY="$API_KEY"
export CLOUD_SECRET="$API_SECRET"
export BOOTSTRAP_SERVERS="$BOOTSTRAP_ENDPOINT"
ENVEOF

source .ccloud_env

log "⏳ Waiting for connector (30 seconds)..."
sleep 30

set +e
playground connector status --connector "DatagenSource_${USER}" 2>/dev/null
set -e

log ""
log "🎯 Next Steps:"
log "   View: https://confluent.cloud/environments/$ENVIRONMENT_ID"
log "   Commands: source $DIR/.ccloud_env && playground topic list"
log ""

log "Delete infrastructure?"
check_if_continue

terraform destroy -auto-approve
rm -f terraform.tfvars .ccloud_env

log "✅ Cleanup complete!"
