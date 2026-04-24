#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Playground Auto Pipeline
#
# Fully automated: Datagen → Kafka → S3
# No manual configuration!
#
# Usage: playground run -f ccloud/terraform-cloud-connector/playground-auto-pipeline.sh
#############################################

log "🚀 Terraform Cloud Connector - Automated Pipeline"
log "=================================================="
log ""
log "This script will automatically create:"
log "  ✅ Confluent Cloud Kafka cluster"
log "  ✅ Datagen source connector (generates data)"
log "  ✅ S3 sink connector (writes to S3)"
log "  ✅ Complete data pipeline!"
log ""

# Auto-setup (same as datagen)
source "$DIR/playground-auto-datagen.sh" --setup-only 2>/dev/null || {
    # Inline setup if sourcing fails
    if ! command -v terraform &> /dev/null; then
        log "📦 Installing Terraform..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew tap hashicorp/tap && brew install hashicorp/tap/terraform
        else
            wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt update && sudo apt install -y terraform
        fi
    fi

    if ! command -v jq &> /dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        else
            sudo apt-get install -y jq
        fi
    fi
}

# Check credentials
log "🔑 Checking credentials..."

if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    if [ -f "$DIR/.env" ]; then
        source "$DIR/.env"
    else
        log ""
        log "⚠️  Confluent Cloud credentials needed:"
        read -p "API Key: " CONFLUENT_CLOUD_API_KEY
        read -s -p "API Secret: " CONFLUENT_CLOUD_API_SECRET
        echo ""
        export CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    fi
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    log ""
    log "⚠️  AWS credentials needed for S3 sink:"
    read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    read -p "S3 Bucket Name: " S3_BUCKET
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
else
    S3_BUCKET="${S3_BUCKET:-kafka-playground-${USER}}"
fi

log "✅ Credentials configured"

cd "$DIR"

# Initialize Terraform
if [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init
fi

# Generate pipeline configuration
CLUSTER_NAME="pg-auto-pipeline-${USER}"
TOPIC_NAME="pipeline_data"

log ""
log "📝 Generating pipeline configuration..."
log "   Cluster: $CLUSTER_NAME"
log "   Topic: $TOPIC_NAME"
log "   S3 Bucket: $S3_BUCKET"

cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
environment_name           = "pg-auto-pipeline-${USER}"
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
      "quickstart"         = "ORDERS"
      "output.data.format" = "JSON"
      "max.interval"       = "1000"
      "iterations"         = "10000000"
      "tasks.max"          = "1"
    }
  },
  {
    name             = "S3Sink_${USER}"
    connector_class  = "S3_SINK"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "topics"                = "$TOPIC_NAME"
      "input.data.format"     = "JSON"
      "s3.bucket.name"        = "$S3_BUCKET"
      "s3.region"             = "${AWS_REGION:-us-east-1}"
      "output.data.format"    = "JSON"
      "time.interval"         = "HOURLY"
      "flush.size"            = "1000"
      "tasks.max"             = "1"
      "aws.access.key.id"     = "$AWS_ACCESS_KEY_ID"
      "aws.secret.access.key" = "$AWS_SECRET_ACCESS_KEY"
    }
  }
]
EOF

log ""
log "🏗️  Deploying complete pipeline..."
log "   (This takes 3-4 minutes)"
terraform apply -auto-approve

# Get outputs
CLUSTER_ID=$(terraform output -json | jq -r '.cluster_id.value')
ENVIRONMENT_ID=$(terraform output -json | jq -r '.environment_id.value')
BOOTSTRAP_ENDPOINT=$(terraform output -json | jq -r '.cluster_bootstrap_endpoint.value')
API_KEY=$(terraform output -json | jq -r '.api_key_id.value')
API_SECRET=$(terraform output -json | jq -r '.api_key_secret.value')

DATAGEN_ID=$(terraform output -json | jq -r '.connector_ids.value."DatagenSource_'${USER}'" // empty')
S3_SINK_ID=$(terraform output -json | jq -r '.connector_ids.value."S3Sink_'${USER}'" // empty')

log ""
log "╔════════════════════════════════════════════════════════╗"
log "║  Pipeline Deployed! 🎉                                 ║"
log "╚════════════════════════════════════════════════════════╝"
log ""
log "📊 Infrastructure:"
log "   Environment: $ENVIRONMENT_ID"
log "   Cluster:     $CLUSTER_ID"
log "   Bootstrap:   $BOOTSTRAP_ENDPOINT"
log ""
log "🔌 Connectors:"
log "   Datagen Source: $DATAGEN_ID"
log "   S3 Sink:        $S3_SINK_ID"
log ""
log "📦 Data Flow:"
log "   Datagen → Topic ($TOPIC_NAME) → S3 ($S3_BUCKET)"
log ""

# Save environment
cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export CLOUD_KEY="$API_KEY"
export CLOUD_SECRET="$API_SECRET"
export BOOTSTRAP_SERVERS="$BOOTSTRAP_ENDPOINT"
ENVEOF

source .ccloud_env

log "⏳ Waiting for connectors to provision (60 seconds)..."
sleep 60

# Verify both connectors
log ""
log "🔍 Verifying pipeline..."

set +e
playground connector status --connector "DatagenSource_${USER}" 2>/dev/null
DATAGEN_STATUS=$?

playground connector status --connector "S3Sink_${USER}" 2>/dev/null
S3_STATUS=$?
set -e

if [ $DATAGEN_STATUS -eq 0 ] && [ $S3_STATUS -eq 0 ]; then
    log "✅ Both connectors are RUNNING!"
    log "✅ Pipeline is operational!"
else
    logwarn "Some connectors may still be starting"
    log "   Check status: https://confluent.cloud"
fi

log ""
log "🎯 Verify Data Flow:"
log ""
log "1. Check messages in Kafka:"
log "   playground topic consume --topic $TOPIC_NAME --max-messages 5"
log ""
log "2. Check S3 bucket:"
log "   aws s3 ls s3://${S3_BUCKET}/topics/${TOPIC_NAME}/"
log ""
log "3. Monitor in Confluent Cloud:"
log "   https://confluent.cloud/environments/$ENVIRONMENT_ID/clusters/$CLUSTER_ID"
log ""
log "4. View connector metrics:"
log "   playground connector status --connector DatagenSource_${USER}"
log "   playground connector status --connector S3Sink_${USER}"
log ""

log "Do you want to delete the pipeline?"
check_if_continue

log "🗑️  Destroying pipeline..."
terraform destroy -auto-approve
rm -f terraform.tfvars .ccloud_env

log "✅ Pipeline cleanup complete!"
