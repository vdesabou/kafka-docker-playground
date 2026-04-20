#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Terraform Cloud Connector Tool
#
# This tool allows you to provision Confluent Cloud
# clusters (lkc-*) and connectors (lcc-*) using Terraform
#############################################

function usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Terraform Cloud Connector Tool for Kafka Docker Playground

OPTIONS:
    --init                  Initialize Terraform
    --plan                  Run Terraform plan
    --apply                 Apply Terraform configuration
    --destroy               Destroy Terraform resources
    --connector-type TYPE   Specify connector type (e.g., S3_SINK, DATAGEN)
    --connector-config FILE Path to connector configuration JSON file
    --cluster-name NAME     Name for the Kafka cluster (default: playground-terraform-cluster)
    --cloud PROVIDER        Cloud provider: AWS, GCP, or AZURE (default: AWS)
    --region REGION         Cloud region (default: us-east-1)
    --help                  Show this help message

EXAMPLES:
    # Initialize and create cluster with S3 Sink connector
    $0 --init --apply --connector-type S3_SINK --connector-config examples/s3-sink.json

    # Plan infrastructure with Datagen connector
    $0 --plan --connector-type DATAGEN --connector-config examples/datagen.json

    # Destroy all resources
    $0 --destroy

ENVIRONMENT VARIABLES:
    CONFLUENT_CLOUD_API_KEY     Confluent Cloud API Key
    CONFLUENT_CLOUD_API_SECRET  Confluent Cloud API Secret

EOF
}

# Default values
ACTION=""
CONNECTOR_TYPE=""
CONNECTOR_CONFIG=""
CLUSTER_NAME="playground-terraform-cluster-${USER}"
CLOUD_PROVIDER="AWS"
CLOUD_REGION="${AWS_REGION:-us-east-1}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --init)
            ACTION="init"
            shift
            ;;
        --plan)
            ACTION="plan"
            shift
            ;;
        --apply)
            ACTION="apply"
            shift
            ;;
        --destroy)
            ACTION="destroy"
            shift
            ;;
        --connector-type)
            CONNECTOR_TYPE="$2"
            shift 2
            ;;
        --connector-config)
            CONNECTOR_CONFIG="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --cloud)
            CLOUD_PROVIDER="$2"
            shift 2
            ;;
        --region)
            CLOUD_REGION="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            logerror "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required environment variables
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    logerror "CONFLUENT_CLOUD_API_KEY environment variable is required"
    exit 1
fi

if [ -z "$CONFLUENT_CLOUD_API_SECRET" ]; then
    logerror "CONFLUENT_CLOUD_API_SECRET environment variable is required"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    logerror "Terraform is not installed. Please install Terraform first."
    logerror "Visit: https://www.terraform.io/downloads"
    exit 1
fi

# Navigate to terraform directory
cd "$DIR"

# Initialize Terraform if needed
if [ "$ACTION" == "init" ] || [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init
fi

# Create terraform.tfvars
log "📝 Creating terraform.tfvars..."
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
environment_name           = "playground-terraform-env-${USER}"
cluster_name               = "$CLUSTER_NAME"
cloud_provider             = "$CLOUD_PROVIDER"
cloud_region               = "$CLOUD_REGION"
EOF

# Add connector configuration if provided
if [ -n "$CONNECTOR_CONFIG" ] && [ -f "$CONNECTOR_CONFIG" ]; then
    log "🔌 Adding connector configuration from $CONNECTOR_CONFIG..."

    # Generate connector tfvars
    cat >> terraform.tfvars << EOF

connector_configs = [
  {
    name             = "${CONNECTOR_TYPE}_${USER}"
    connector_class  = "$CONNECTOR_TYPE"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config           = $(cat $CONNECTOR_CONFIG)
  }
]
EOF
fi

# Execute Terraform action
case $ACTION in
    init)
        log "✅ Terraform initialized successfully"
        ;;
    plan)
        log "📋 Running Terraform plan..."
        terraform plan
        ;;
    apply)
        log "🚀 Applying Terraform configuration..."
        terraform apply -auto-approve

        # Display outputs
        log ""
        log "✅ Infrastructure created successfully!"
        log ""
        log "📊 Cluster Details:"
        terraform output -json | jq -r '.cluster_id.value' | xargs -I {} echo "   Cluster ID: {}"
        terraform output -json | jq -r '.cluster_bootstrap_endpoint.value' | xargs -I {} echo "   Bootstrap: {}"
        terraform output -json | jq -r '.environment_id.value' | xargs -I {} echo "   Environment: {}"

        if terraform output -json | jq -e '.connector_ids.value | length > 0' > /dev/null 2>&1; then
            log ""
            log "🔌 Connector Details:"
            terraform output -json | jq -r '.connector_ids.value | to_entries[] | "   \(.key): \(.value)"'
        fi

        # Save cluster info for playground use
        CLUSTER_ID=$(terraform output -json | jq -r '.cluster_id.value')
        API_KEY=$(terraform output -json | jq -r '.api_key_id.value')
        API_SECRET=$(terraform output -json | jq -r '.api_key_secret.value')

        log ""
        log "💾 Saving cluster configuration to .ccloud_env..."
        cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export CLOUD_KEY="$API_KEY"
export CLOUD_SECRET="$API_SECRET"
ENVEOF

        log ""
        log "🎯 To use this cluster with playground:"
        log "   source $DIR/.ccloud_env"
        ;;
    destroy)
        log "🗑️  Destroying Terraform resources..."
        terraform destroy -auto-approve
        rm -f terraform.tfvars .ccloud_env
        log "✅ Resources destroyed successfully"
        ;;
    *)
        logerror "No action specified. Use --init, --plan, --apply, or --destroy"
        usage
        exit 1
        ;;
esac
