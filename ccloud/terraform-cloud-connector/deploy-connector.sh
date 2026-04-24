#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

#############################################
# Interactive Terraform Connector Deployment
#
# Prompts for:
# 1. Confluent Cloud API credentials
# 2. Environment selection (existing or new)
# 3. Cluster selection (existing or new)
# 4. Connector configuration
#
# Usage:
#   ./deploy-connector.sh
#   OR
#   playground run -f ccloud/terraform-cloud-connector/deploy-connector.sh
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}$1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Confluent Cloud Connector Deployment Tool         ║${NC}"
echo -e "${CYAN}║     Interactive Mode                                   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$DIR"

#############################################
# Step 1: Confluent Cloud Credentials
#############################################

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} Step 1: Confluent Cloud API Credentials${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "$DIR/.env" ]; then
    source "$DIR/.env"
    if [ -n "$CONFLUENT_CLOUD_API_KEY" ]; then
        info "Found saved credentials in .env file"
        read -p "Use saved credentials? (y/n) [y]: " USE_SAVED
        USE_SAVED=${USE_SAVED:-y}

        if [[ ! "$USE_SAVED" =~ ^[Yy]$ ]]; then
            CONFLUENT_CLOUD_API_KEY=""
            CONFLUENT_CLOUD_API_SECRET=""
        fi
    fi
fi

if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    echo ""
    info "Get your API credentials from: https://confluent.cloud"
    info "Navigate to: Administration → Cloud API Keys → Add Key"
    echo ""

    read -p "Confluent Cloud API Key: " CONFLUENT_CLOUD_API_KEY
    read -sp "Confluent Cloud API Secret: " CONFLUENT_CLOUD_API_SECRET
    echo ""

    # Save credentials
    cat > "$DIR/.env" << EOF
export CONFLUENT_CLOUD_API_KEY="$CONFLUENT_CLOUD_API_KEY"
export CONFLUENT_CLOUD_API_SECRET="$CONFLUENT_CLOUD_API_SECRET"
EOF
    chmod 600 "$DIR/.env"
    success "Credentials saved to .env"
fi

# Validate credentials
info "Validating credentials..."
VALIDATION=$(curl -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  "https://api.confluent.cloud/org/v2/environments?page_size=1" | jq -r '.errors // empty')

if [ -n "$VALIDATION" ]; then
    error "Invalid credentials! Please check your API key and secret."
    rm -f "$DIR/.env"
    exit 1
fi

success "Credentials validated!"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    info "Initializing Terraform..."
    terraform init > /dev/null 2>&1
fi

#############################################
# Step 2: Environment Selection
#############################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} Step 2: Environment Selection${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Fetching your environments..."
ENV_RESPONSE=$(curl -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  "https://api.confluent.cloud/org/v2/environments")

ENV_COUNT=$(echo "$ENV_RESPONSE" | jq -r '.data | length')

if [ "$ENV_COUNT" -eq 0 ]; then
    warn "No environments found. Creating new environment."
    USE_EXISTING_ENVIRONMENT="false"
    read -p "Environment name [terraform-env]: " ENVIRONMENT_NAME
    ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-"terraform-env"}
    ENVIRONMENT_ID=""
else
    echo ""
    echo "Available Environments:"
    echo "$ENV_RESPONSE" | jq -r '.data[] | "  [\(.id)] \(.display_name)"'
    echo ""

    read -p "Use existing environment? (y/n) [y]: " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-y}

    if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
        echo ""
        read -p "Enter Environment ID (e.g., env-xxxxx or t36303): " ENVIRONMENT_ID

        # Validate environment
        ENV_NAME=$(echo "$ENV_RESPONSE" | jq -r --arg id "$ENVIRONMENT_ID" \
          '.data[] | select(.id == $id) | .display_name')

        if [ -z "$ENV_NAME" ]; then
            error "Environment $ENVIRONMENT_ID not found!"
            exit 1
        fi

        success "Selected environment: $ENV_NAME ($ENVIRONMENT_ID)"
        USE_EXISTING_ENVIRONMENT="true"
    else
        read -p "New environment name [terraform-env]: " ENVIRONMENT_NAME
        ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-"terraform-env"}
        ENVIRONMENT_ID=""
        USE_EXISTING_ENVIRONMENT="false"
        success "Will create new environment: $ENVIRONMENT_NAME"
    fi
fi

#############################################
# Step 3: Cluster Selection
#############################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} Step 3: Kafka Cluster Selection${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

USE_EXISTING_CLUSTER="false"
EXISTING_CLUSTER_ID=""

if [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    info "Fetching clusters in environment $ENVIRONMENT_ID..."
    CLUSTER_RESPONSE=$(curl -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
      "https://api.confluent.cloud/cmk/v2/clusters?environment=$ENVIRONMENT_ID")

    CLUSTER_COUNT=$(echo "$CLUSTER_RESPONSE" | jq -r '.data | length')

    if [ "$CLUSTER_COUNT" -gt 0 ]; then
        echo ""
        echo "Available Clusters:"
        echo "$CLUSTER_RESPONSE" | jq -r '.data[] | "  [\(.id)] \(.spec.display_name) - \(.spec.cloud):\(.spec.region) (\(.spec.availability))"'
        echo ""

        read -p "Use existing cluster? (y/n) [y]: " USE_EXISTING_CLUSTER_INPUT
        USE_EXISTING_CLUSTER_INPUT=${USE_EXISTING_CLUSTER_INPUT:-y}

        if [[ "$USE_EXISTING_CLUSTER_INPUT" =~ ^[Yy]$ ]]; then
            echo ""
            read -p "Enter Cluster ID (e.g., lkc-xxxxx): " EXISTING_CLUSTER_ID

            # Validate cluster
            CLUSTER_INFO=$(echo "$CLUSTER_RESPONSE" | jq -r --arg id "$EXISTING_CLUSTER_ID" \
              '.data[] | select(.id == $id)')

            if [ -z "$CLUSTER_INFO" ]; then
                error "Cluster $EXISTING_CLUSTER_ID not found in environment $ENVIRONMENT_ID!"
                exit 1
            fi

            CLUSTER_NAME=$(echo "$CLUSTER_INFO" | jq -r '.spec.display_name')
            CLOUD_PROVIDER=$(echo "$CLUSTER_INFO" | jq -r '.spec.cloud')
            CLOUD_REGION=$(echo "$CLUSTER_INFO" | jq -r '.spec.region')

            success "Selected cluster: $CLUSTER_NAME ($EXISTING_CLUSTER_ID)"
            info "Cloud: $CLOUD_PROVIDER, Region: $CLOUD_REGION"
            USE_EXISTING_CLUSTER="true"
        fi
    fi
fi

if [[ "$USE_EXISTING_CLUSTER" != "true" ]]; then
    info "Creating new Kafka cluster..."
    echo ""

    read -p "Cluster name [kafka-cluster-$(date +%s)]: " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-"kafka-cluster-$(date +%s)"}

    echo ""
    echo "Cloud Providers:"
    echo "  1) AWS"
    echo "  2) GCP"
    echo "  3) Azure"
    read -p "Select cloud provider [1]: " CLOUD_CHOICE
    CLOUD_CHOICE=${CLOUD_CHOICE:-1}

    case $CLOUD_CHOICE in
        1) CLOUD_PROVIDER="AWS"; DEFAULT_REGION="us-east-1" ;;
        2) CLOUD_PROVIDER="GCP"; DEFAULT_REGION="us-central1" ;;
        3) CLOUD_PROVIDER="AZURE"; DEFAULT_REGION="eastus" ;;
        *) CLOUD_PROVIDER="AWS"; DEFAULT_REGION="us-east-1" ;;
    esac

    read -p "Region [$DEFAULT_REGION]: " CLOUD_REGION
    CLOUD_REGION=${CLOUD_REGION:-$DEFAULT_REGION}

    echo ""
    echo "Cluster Availability:"
    echo "  1) SINGLE_ZONE (Basic - lower cost)"
    echo "  2) MULTI_ZONE (High availability)"
    read -p "Select [1]: " AVAILABILITY_CHOICE
    AVAILABILITY_CHOICE=${AVAILABILITY_CHOICE:-1}

    case $AVAILABILITY_CHOICE in
        1) CLUSTER_AVAILABILITY="SINGLE_ZONE" ;;
        2) CLUSTER_AVAILABILITY="MULTI_ZONE" ;;
        *) CLUSTER_AVAILABILITY="SINGLE_ZONE" ;;
    esac

    success "Will create: $CLUSTER_NAME on $CLOUD_PROVIDER:$CLOUD_REGION ($CLUSTER_AVAILABILITY)"
fi

#############################################
# Step 4: Connector Configuration
#############################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} Step 4: Connector Configuration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Select Connector Type:"
echo "  1) DatagenSource - Generate sample data (PAGEVIEWS, ORDERS, USERS)"
echo "  2) DatagenSource - ORDERS"
echo "  3) DatagenSource - USERS"
echo "  4) DatagenSource - CLICKSTREAM"
echo "  5) Custom configuration"
echo ""

read -p "Select connector type [1]: " CONNECTOR_CHOICE
CONNECTOR_CHOICE=${CONNECTOR_CHOICE:-1}

read -p "Connector name [datagen-$(date +%s)]: " CONNECTOR_NAME
CONNECTOR_NAME=${CONNECTOR_NAME:-"datagen-$(date +%s)"}

case $CONNECTOR_CHOICE in
    1)
        CONNECTOR_CLASS="DatagenSource"
        read -p "Topic name [pageviews]: " TOPIC_NAME
        TOPIC_NAME=${TOPIC_NAME:-"pageviews"}
        QUICKSTART="PAGEVIEWS"
        ;;
    2)
        CONNECTOR_CLASS="DatagenSource"
        read -p "Topic name [orders]: " TOPIC_NAME
        TOPIC_NAME=${TOPIC_NAME:-"orders"}
        QUICKSTART="ORDERS"
        ;;
    3)
        CONNECTOR_CLASS="DatagenSource"
        read -p "Topic name [users]: " TOPIC_NAME
        TOPIC_NAME=${TOPIC_NAME:-"users"}
        QUICKSTART="USERS"
        ;;
    4)
        CONNECTOR_CLASS="DatagenSource"
        read -p "Topic name [clickstream]: " TOPIC_NAME
        TOPIC_NAME=${TOPIC_NAME:-"clickstream"}
        QUICKSTART="CLICKSTREAM"
        ;;
    5)
        read -p "Connector class: " CONNECTOR_CLASS
        read -p "Topic name: " TOPIC_NAME
        read -p "Quickstart template: " QUICKSTART
        ;;
    *)
        CONNECTOR_CLASS="DatagenSource"
        TOPIC_NAME="pageviews"
        QUICKSTART="PAGEVIEWS"
        ;;
esac

success "Connector configured: $CONNECTOR_NAME ($CONNECTOR_CLASS)"
info "Topic: $TOPIC_NAME, Template: $QUICKSTART"

#############################################
# Step 5: Generate Terraform Configuration
#############################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} Step 5: Review Configuration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Deployment Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    echo "Environment:  $ENVIRONMENT_ID (existing)"
else
    echo "Environment:  $ENVIRONMENT_NAME (new)"
fi

if [[ "$USE_EXISTING_CLUSTER" == "true" ]]; then
    echo "Cluster:      $EXISTING_CLUSTER_ID (existing)"
    echo "              $CLUSTER_NAME - $CLOUD_PROVIDER:$CLOUD_REGION"
else
    echo "Cluster:      $CLUSTER_NAME (new)"
    echo "              $CLOUD_PROVIDER:$CLOUD_REGION ($CLUSTER_AVAILABILITY)"
fi

echo "Connector:    $CONNECTOR_NAME"
echo "Type:         $CONNECTOR_CLASS"
echo "Topic:        $TOPIC_NAME"
echo "Template:     $QUICKSTART"
echo ""

read -p "Proceed with deployment? (y/n) [y]: " PROCEED
PROCEED=${PROCEED:-y}

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    warn "Deployment cancelled by user"
    exit 0
fi

# Generate terraform.tfvars
info "Generating Terraform configuration..."

cat > terraform.tfvars << EOF
# Confluent Cloud Credentials
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"

# Environment Configuration
use_existing_environment = $USE_EXISTING_ENVIRONMENT
EOF

if [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    echo "environment_id           = \"$ENVIRONMENT_ID\"" >> terraform.tfvars
else
    cat >> terraform.tfvars << EOF
environment_name         = "$ENVIRONMENT_NAME"
stream_governance_package = "ESSENTIALS"
EOF
fi

# Cluster Configuration
if [[ "$USE_EXISTING_CLUSTER" != "true" ]]; then
    cat >> terraform.tfvars << EOF

# Kafka Cluster Configuration
cluster_name         = "$CLUSTER_NAME"
cloud_provider       = "$CLOUD_PROVIDER"
cloud_region         = "$CLOUD_REGION"
cluster_availability = "$CLUSTER_AVAILABILITY"
EOF
fi

# Connector Configuration
cat >> terraform.tfvars << EOF

# Connector Configuration
connector_configs = [
  {
    name             = "$CONNECTOR_NAME"
    connector_class  = "$CONNECTOR_CLASS"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = {
      "kafka.topic"        = "$TOPIC_NAME"
      "quickstart"         = "$QUICKSTART"
      "output.data.format" = "JSON"
      "tasks.max"          = "1"
    }
  }
]
EOF

success "Configuration generated: terraform.tfvars"

#############################################
# Step 6: Deploy with Terraform
#############################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} Step 6: Deploying to Confluent Cloud${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ "$USE_EXISTING_CLUSTER" == "true" ]]; then
    warn "Deploying connector to existing cluster..."
    info "This will take approximately 2-3 minutes"
else
    warn "Deploying full infrastructure (environment + cluster + connector)..."
    info "This will take approximately 3-5 minutes"
fi

echo ""

terraform apply -auto-approve

#############################################
# Step 7: Display Results
#############################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} ✓ Deployment Complete!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get outputs
DEPLOYED_ENV_ID=$(terraform output -json 2>/dev/null | jq -r '.environment_id.value // empty')
DEPLOYED_CLUSTER_ID=$(terraform output -json 2>/dev/null | jq -r '.cluster_id.value // empty')
DEPLOYED_CONNECTOR_IDS=$(terraform output -json 2>/dev/null | jq -r '.connector_ids.value // empty')
CONNECTOR_STATUS=$(terraform output -json 2>/dev/null | jq -r '.connector_status.value // empty')

if [ -z "$DEPLOYED_ENV_ID" ] && [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    DEPLOYED_ENV_ID=$ENVIRONMENT_ID
fi

if [ -z "$DEPLOYED_CLUSTER_ID" ] && [[ "$USE_EXISTING_CLUSTER" == "true" ]]; then
    DEPLOYED_CLUSTER_ID=$EXISTING_CLUSTER_ID
fi

echo "Deployment Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Environment:  $DEPLOYED_ENV_ID"
echo "Cluster:      $DEPLOYED_CLUSTER_ID"

if [ -n "$DEPLOYED_CONNECTOR_IDS" ]; then
    echo ""
    echo "Connectors:"
    echo "$DEPLOYED_CONNECTOR_IDS" | jq -r 'to_entries[] | "  \(.key): \(.value)"'

    if [ -n "$CONNECTOR_STATUS" ]; then
        echo ""
        echo "Status:"
        echo "$CONNECTOR_STATUS" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    fi
fi

echo ""
echo "View in Confluent Cloud:"
echo "  https://confluent.cloud/environments/$DEPLOYED_ENV_ID"
echo ""

# Save deployment info
cat > .deployment_info << EOF
ENVIRONMENT_ID=$DEPLOYED_ENV_ID
CLUSTER_ID=$DEPLOYED_CLUSTER_ID
CONNECTOR_NAME=$CONNECTOR_NAME
DEPLOYED_AT=$(date)
EOF

success "Deployment info saved to .deployment_info"

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. View resources in Confluent Cloud UI"
echo "  2. Check connector status and logs"
echo "  3. Consume messages from topic: $TOPIC_NAME"
echo ""
echo "To clean up resources later, run:"
echo "  cd $DIR && terraform destroy"
echo ""

success "Deployment complete! 🚀"
