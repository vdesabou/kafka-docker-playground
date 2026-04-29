#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Playground Auto Datagen
#
# Fully automated Datagen deployment
# No manual configuration needed!
#
# Usage: playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh
#############################################

log "🚀 Terraform Cloud Connector - Automated Datagen"
log "=================================================="
log ""
log "This script will automatically:"
log "  ✅ Install Terraform (if needed)"
log "  ✅ Configure credentials"
log "  ✅ Deploy Confluent Cloud cluster"
log "  ✅ Create Datagen connector"
log ""

# Auto-setup function
function auto_setup() {
    log "🔧 Running automated setup..."

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log "📦 Installing Terraform..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew tap hashicorp/tap
                brew install hashicorp/tap/terraform
            else
                logerror "Homebrew not found. Please install from https://brew.sh"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt update && sudo apt install -y terraform
        fi
        log "✅ Terraform installed"
    else
        log "✅ Terraform already installed ($(terraform version -json | jq -r '.terraform_version'))"
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        log "📦 Installing jq..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        else
            sudo apt-get install -y jq
        fi
        log "✅ jq installed"
    fi
}

# Check and setup credentials
function setup_credentials() {
    log "🔑 Checking Confluent Cloud credentials..."

    if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
        # Check if .env exists
        if [ -f "$DIR/.env" ]; then
            log "Loading credentials from .env file..."
            source "$DIR/.env"
        else
            log ""
            log "⚠️  Confluent Cloud credentials needed!"
            log "   Get your API keys at: https://confluent.cloud/settings/api-keys"
            log ""
            read -p "API Key: " API_KEY
            read -s -p "API Secret: " API_SECRET
            echo ""

            if [ -z "$API_KEY" ] || [ -z "$API_SECRET" ]; then
                logerror "Credentials cannot be empty"
                exit 1
            fi

            export CONFLUENT_CLOUD_API_KEY="$API_KEY"
            export CONFLUENT_CLOUD_API_SECRET="$API_SECRET"

            # Save for future runs
            cat > "$DIR/.env" << EOF
export CONFLUENT_CLOUD_API_KEY="$API_KEY"
export CONFLUENT_CLOUD_API_SECRET="$API_SECRET"
EOF
            log "✅ Credentials saved to .env"
        fi
    fi

    if [ -z "$CONFLUENT_CLOUD_API_KEY" ] || [ -z "$CONFLUENT_CLOUD_API_SECRET" ]; then
        logerror "CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET are required"
        exit 1
    fi

    log "✅ Credentials configured"
}

# Main execution
auto_setup
setup_credentials

cd "$DIR"

# Initialize Terraform
if [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init
else
    log "✅ Terraform already initialized"
fi

# Generate configuration
CLUSTER_NAME="pg-auto-datagen-${USER}"
TOPIC_NAME="pageviews"

log ""
log "📝 Generating Terraform configuration..."
log "   Cluster: $CLUSTER_NAME"
log "   Topic: $TOPIC_NAME"
log "   Cloud: AWS"
log "   Region: ${AWS_REGION:-us-east-1}"

cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
environment_name           = "pg-auto-env-${USER}"
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
      "output.data.format" = "JSON"
      "max.interval"       = "1000"
      "iterations"         = "10000000"
      "tasks.max"          = "1"
    }
  }
]
EOF

log ""
log "🏗️  Deploying Confluent Cloud infrastructure..."
log "   (This takes 2-3 minutes)"
terraform apply -auto-approve

# Get outputs
CLUSTER_ID=$(terraform output -json | jq -r '.cluster_id.value')
ENVIRONMENT_ID=$(terraform output -json | jq -r '.environment_id.value')
CONNECTOR_ID=$(terraform output -json | jq -r '.connector_ids.value | to_entries[0].value // empty')
API_KEY=$(terraform output -json | jq -r '.api_key_id.value')
API_SECRET=$(terraform output -json | jq -r '.api_key_secret.value')
BOOTSTRAP_ENDPOINT=$(terraform output -json | jq -r '.cluster_bootstrap_endpoint.value')

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

# Save for playground commands
log "💾 Saving environment configuration..."
cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export CLOUD_KEY="$API_KEY"
export CLOUD_SECRET="$API_SECRET"
export BOOTSTRAP_SERVERS="$BOOTSTRAP_ENDPOINT"
ENVEOF

source .ccloud_env

log ""
log "⏳ Waiting for connector to provision (30 seconds)..."
sleep 30

# Verify connector
log "🔍 Verifying connector status..."
set +e
playground connector status --connector "DatagenSource_${USER}" 2>/dev/null
CONNECTOR_STATUS=$?
set -e

if [ $CONNECTOR_STATUS -eq 0 ]; then
    log "✅ Connector is RUNNING"
else
    logwarn "Could not verify with playground command"
    log "   Check manually: https://confluent.cloud"
fi

log ""
log "🎯 What You Can Do Now:"
log ""
log "1. View in Confluent Cloud:"
log "   https://confluent.cloud/environments/$ENVIRONMENT_ID/clusters/$CLUSTER_ID"
log ""
log "2. Use playground commands:"
log "   source $DIR/.ccloud_env"
log "   playground topic list"
log "   playground connector list"
log "   playground topic consume --topic $TOPIC_NAME"
log ""
log "3. View Terraform state:"
log "   cd $DIR && terraform output"
log ""
log "4. Check connector status:"
log "   playground connector status --connector DatagenSource_${USER}"
log ""

log "Do you want to delete the infrastructure?"
check_if_continue

log "🗑️  Destroying resources..."
terraform destroy -auto-approve
rm -f terraform.tfvars .ccloud_env

log "✅ Cleanup complete!"
