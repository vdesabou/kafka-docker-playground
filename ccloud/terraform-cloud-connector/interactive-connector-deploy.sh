#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Interactive Connector Deployment
#
# Guides users through:
# 1. Environment selection (new or existing)
# 2. Cluster selection (new or existing)
# 3. Connector configuration and deployment
#
# Usage: playground run -f ccloud/terraform-cloud-connector/interactive-connector-deploy.sh
#############################################

log "🚀 Interactive Connector Deployment"
log "===================================="
log ""

# Check credentials
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    if [ -f "$DIR/.env" ]; then
        source "$DIR/.env"
    fi

    if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
        log "📋 Please provide your Confluent Cloud credentials:"
        read -p "API Key: " CONFLUENT_CLOUD_API_KEY
        read -sp "API Secret: " CONFLUENT_CLOUD_API_SECRET
        echo ""

        # Save credentials
        cat > "$DIR/.env" << EOF
export CONFLUENT_CLOUD_API_KEY="$CONFLUENT_CLOUD_API_KEY"
export CONFLUENT_CLOUD_API_SECRET="$CONFLUENT_CLOUD_API_SECRET"
EOF
        chmod 600 "$DIR/.env"
    fi
fi

log "✅ Credentials configured"

cd "$DIR"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    log "🔧 Initializing Terraform..."
    terraform init > /dev/null 2>&1
fi

#############################################
# Step 1: Environment Selection
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Step 1: Environment Selection"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

# Fetch existing environments
log "📋 Fetching available environments..."
ENV_RESPONSE=$(curl -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  "https://api.confluent.cloud/org/v2/environments")

ENV_COUNT=$(echo "$ENV_RESPONSE" | jq -r '.data | length')

if [ "$ENV_COUNT" -gt 0 ]; then
    log ""
    log "Available Environments:"
    echo "$ENV_RESPONSE" | jq -r '.data[] | "  [\(.id)] \(.display_name)"'
    log ""

    read -p "Use existing environment? (y/n): " USE_EXISTING_ENV

    if [[ "$USE_EXISTING_ENV" =~ ^[Yy]$ ]]; then
        read -p "Enter Environment ID (e.g., env-xxxxx): " ENVIRONMENT_ID

        # Validate environment exists
        ENV_NAME=$(echo "$ENV_RESPONSE" | jq -r --arg id "$ENVIRONMENT_ID" '.data[] | select(.id == $id) | .display_name')
        if [ -z "$ENV_NAME" ]; then
            logerror "Environment $ENVIRONMENT_ID not found!"
            exit 1
        fi

        log "✅ Using existing environment: $ENV_NAME ($ENVIRONMENT_ID)"
        USE_EXISTING_ENVIRONMENT="true"
    else
        read -p "Enter new environment name: " ENV_NAME
        ENVIRONMENT_ID=""
        USE_EXISTING_ENVIRONMENT="false"
        log "✅ Will create new environment: $ENV_NAME"
    fi
else
    log "No existing environments found. Creating new environment."
    read -p "Enter environment name: " ENV_NAME
    ENVIRONMENT_ID=""
    USE_EXISTING_ENVIRONMENT="false"
fi

#############################################
# Step 2: Cluster Selection
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Step 2: Kafka Cluster Selection"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

USE_EXISTING_CLUSTER="false"
CLUSTER_ID=""

if [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    # Fetch clusters in the selected environment
    log "📋 Fetching clusters in environment $ENVIRONMENT_ID..."
    CLUSTER_RESPONSE=$(curl -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
      "https://api.confluent.cloud/cmk/v2/clusters?environment=$ENVIRONMENT_ID")

    CLUSTER_COUNT=$(echo "$CLUSTER_RESPONSE" | jq -r '.data | length')

    if [ "$CLUSTER_COUNT" -gt 0 ]; then
        log ""
        log "Available Clusters in $ENVIRONMENT_ID:"
        echo "$CLUSTER_RESPONSE" | jq -r '.data[] | "  [\(.id)] \(.spec.display_name) - \(.spec.cloud):\(.spec.region) (\(.spec.availability))"'
        log ""

        read -p "Use existing cluster? (y/n): " USE_EXISTING_CLUSTER_INPUT

        if [[ "$USE_EXISTING_CLUSTER_INPUT" =~ ^[Yy]$ ]]; then
            read -p "Enter Cluster ID (e.g., lkc-xxxxx): " CLUSTER_ID

            # Validate cluster exists
            CLUSTER_INFO=$(echo "$CLUSTER_RESPONSE" | jq -r --arg id "$CLUSTER_ID" '.data[] | select(.id == $id)')
            if [ -z "$CLUSTER_INFO" ]; then
                logerror "Cluster $CLUSTER_ID not found in environment $ENVIRONMENT_ID!"
                exit 1
            fi

            CLUSTER_NAME=$(echo "$CLUSTER_INFO" | jq -r '.spec.display_name')
            CLUSTER_CLOUD=$(echo "$CLUSTER_INFO" | jq -r '.spec.cloud')
            CLUSTER_REGION=$(echo "$CLUSTER_INFO" | jq -r '.spec.region')
            CLUSTER_AVAILABILITY=$(echo "$CLUSTER_INFO" | jq -r '.spec.availability')

            log "✅ Using existing cluster: $CLUSTER_NAME ($CLUSTER_ID)"
            log "   Cloud: $CLUSTER_CLOUD, Region: $CLUSTER_REGION"
            USE_EXISTING_CLUSTER="true"
        fi
    fi
fi

if [[ "$USE_EXISTING_CLUSTER" != "true" ]]; then
    log "Creating new Kafka cluster..."
    log ""

    # Cluster configuration
    read -p "Cluster name [pg-connector-$(date +%s)]: " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-"pg-connector-$(date +%s)"}

    log ""
    log "Select Cloud Provider:"
    log "  1) AWS"
    log "  2) GCP"
    log "  3) Azure"
    read -p "Choice [1]: " CLOUD_CHOICE
    CLOUD_CHOICE=${CLOUD_CHOICE:-1}

    case $CLOUD_CHOICE in
        1) CLOUD_PROVIDER="AWS"; DEFAULT_REGION="us-east-1" ;;
        2) CLOUD_PROVIDER="GCP"; DEFAULT_REGION="us-central1" ;;
        3) CLOUD_PROVIDER="AZURE"; DEFAULT_REGION="eastus" ;;
        *) CLOUD_PROVIDER="AWS"; DEFAULT_REGION="us-east-1" ;;
    esac

    read -p "Region [$DEFAULT_REGION]: " CLOUD_REGION
    CLOUD_REGION=${CLOUD_REGION:-$DEFAULT_REGION}

    log ""
    log "Select Availability:"
    log "  1) SINGLE_ZONE (Basic - lower cost)"
    log "  2) MULTI_ZONE (High availability)"
    read -p "Choice [1]: " AVAILABILITY_CHOICE
    AVAILABILITY_CHOICE=${AVAILABILITY_CHOICE:-1}

    case $AVAILABILITY_CHOICE in
        1) CLUSTER_AVAILABILITY="SINGLE_ZONE" ;;
        2) CLUSTER_AVAILABILITY="MULTI_ZONE" ;;
        *) CLUSTER_AVAILABILITY="SINGLE_ZONE" ;;
    esac

    log "✅ Will create new cluster: $CLUSTER_NAME"
    log "   Provider: $CLOUD_PROVIDER, Region: $CLOUD_REGION, Availability: $CLUSTER_AVAILABILITY"
fi

#############################################
# Step 3: Connector Selection
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Step 3: Connector Configuration"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

log "Popular Connectors:"
log "  1) DatagenSource - Generate sample data"
log "  2) S3 Sink - Write to AWS S3"
log "  3) S3 Source - Read from AWS S3"
log "  4) PostgreSQL CDC Source - Database change capture"
log "  5) MongoDB Sink - Write to MongoDB"
log "  6) Custom - Enter connector class manually"
log ""

read -p "Select connector type [1]: " CONNECTOR_CHOICE
CONNECTOR_CHOICE=${CONNECTOR_CHOICE:-1}

read -p "Connector name [my-connector-$(date +%s)]: " CONNECTOR_NAME
CONNECTOR_NAME=${CONNECTOR_NAME:-"my-connector-$(date +%s)"}

case $CONNECTOR_CHOICE in
    1)
        # DatagenSource
        CONNECTOR_CLASS="DatagenSource"
        read -p "Topic name [pageviews]: " TOPIC_NAME
        TOPIC_NAME=${TOPIC_NAME:-"pageviews"}

        log ""
        log "Datagen Templates:"
        log "  1) PAGEVIEWS"
        log "  2) ORDERS"
        log "  3) USERS"
        log "  4) CLICKSTREAM"
        read -p "Select template [1]: " TEMPLATE_CHOICE
        TEMPLATE_CHOICE=${TEMPLATE_CHOICE:-1}

        case $TEMPLATE_CHOICE in
            1) QUICKSTART="PAGEVIEWS" ;;
            2) QUICKSTART="ORDERS" ;;
            3) QUICKSTART="USERS" ;;
            4) QUICKSTART="CLICKSTREAM" ;;
            *) QUICKSTART="PAGEVIEWS" ;;
        esac

        CONNECTOR_CONFIG=$(cat <<EOF
{
  "kafka.topic": "$TOPIC_NAME",
  "quickstart": "$QUICKSTART",
  "output.data.format": "JSON",
  "tasks.max": "1"
}
EOF
)
        ;;

    2)
        # S3 Sink
        CONNECTOR_CLASS="S3_SINK"
        read -p "S3 Bucket name: " S3_BUCKET
        read -p "Topics to export (comma-separated): " TOPICS
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY
        read -sp "AWS Secret Access Key: " AWS_SECRET_KEY
        echo ""

        CONNECTOR_CONFIG=$(cat <<EOF
{
  "topics": "$TOPICS",
  "s3.bucket.name": "$S3_BUCKET",
  "s3.region": "us-east-1",
  "flush.size": "1000",
  "tasks.max": "1",
  "aws.access.key.id": "$AWS_ACCESS_KEY",
  "aws.secret.access.key": "$AWS_SECRET_KEY",
  "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
  "storage.class": "io.confluent.connect.s3.storage.S3Storage"
}
EOF
)
        ;;

    3)
        # S3 Source
        CONNECTOR_CLASS="S3_SOURCE"
        read -p "S3 Bucket name: " S3_BUCKET
        read -p "Target topic: " TOPIC_NAME
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY
        read -sp "AWS Secret Access Key: " AWS_SECRET_KEY
        echo ""

        CONNECTOR_CONFIG=$(cat <<EOF
{
  "s3.bucket.name": "$S3_BUCKET",
  "s3.region": "us-east-1",
  "kafka.topic": "$TOPIC_NAME",
  "tasks.max": "1",
  "aws.access.key.id": "$AWS_ACCESS_KEY",
  "aws.secret.access.key": "$AWS_SECRET_KEY",
  "format.class": "io.confluent.connect.s3.format.json.JsonFormat"
}
EOF
)
        ;;

    4)
        # PostgreSQL CDC Source
        CONNECTOR_CLASS="PostgresCdcSource"
        read -p "Database hostname: " DB_HOST
        read -p "Database port [5432]: " DB_PORT
        DB_PORT=${DB_PORT:-5432}
        read -p "Database name: " DB_NAME
        read -p "Database user: " DB_USER
        read -sp "Database password: " DB_PASSWORD
        echo ""
        read -p "Table include list (e.g., public.users): " TABLE_INCLUDE

        CONNECTOR_CONFIG=$(cat <<EOF
{
  "database.hostname": "$DB_HOST",
  "database.port": "$DB_PORT",
  "database.user": "$DB_USER",
  "database.password": "$DB_PASSWORD",
  "database.dbname": "$DB_NAME",
  "database.server.name": "postgres-$(date +%s)",
  "table.include.list": "$TABLE_INCLUDE",
  "plugin.name": "pgoutput",
  "tasks.max": "1"
}
EOF
)
        ;;

    5)
        # MongoDB Sink
        CONNECTOR_CLASS="MongoDbAtlasSink"
        read -p "MongoDB connection string: " MONGO_URI
        read -p "Database name: " MONGO_DB
        read -p "Topics to sync (comma-separated): " TOPICS

        CONNECTOR_CONFIG=$(cat <<EOF
{
  "topics": "$TOPICS",
  "connection.uri": "$MONGO_URI",
  "database": "$MONGO_DB",
  "tasks.max": "1"
}
EOF
)
        ;;

    6)
        # Custom connector
        read -p "Connector class: " CONNECTOR_CLASS
        log ""
        log "Enter connector configuration (JSON format)."
        log "Press Ctrl+D when done:"
        CONNECTOR_CONFIG=$(cat)
        ;;

    *)
        CONNECTOR_CLASS="DatagenSource"
        CONNECTOR_CONFIG='{"kafka.topic": "pageviews", "quickstart": "PAGEVIEWS", "output.data.format": "JSON", "tasks.max": "1"}'
        ;;
esac

#############################################
# Step 4: Generate Configuration
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Step 4: Generating Configuration"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

# Parse connector config from JSON
CONNECTOR_CONFIG_TF=$(echo "$CONNECTOR_CONFIG" | jq -r 'to_entries | map("      \"\(.key)\" = \"\(.value)\"") | join("\n")')

# Generate terraform.tfvars
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"

# Environment Configuration
use_existing_environment = $USE_EXISTING_ENVIRONMENT
EOF

if [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    cat >> terraform.tfvars << EOF
environment_id           = "$ENVIRONMENT_ID"
EOF
else
    cat >> terraform.tfvars << EOF
environment_name         = "$ENV_NAME"
stream_governance_package = "ESSENTIALS"
EOF
fi

# Cluster Configuration
if [[ "$USE_EXISTING_CLUSTER" != "true" ]]; then
    cat >> terraform.tfvars << EOF

# Kafka Cluster Configuration
cluster_name        = "$CLUSTER_NAME"
cloud_provider      = "$CLOUD_PROVIDER"
cloud_region        = "$CLOUD_REGION"
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
$CONNECTOR_CONFIG_TF
    }
  }
]
EOF

log "✅ Configuration generated"

#############################################
# Step 5: Review and Deploy
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Step 5: Review Configuration"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

log "📋 Deployment Summary:"
log ""
if [[ "$USE_EXISTING_ENVIRONMENT" == "true" ]]; then
    log "Environment: $ENVIRONMENT_ID (existing)"
else
    log "Environment: $ENV_NAME (new)"
fi

if [[ "$USE_EXISTING_CLUSTER" == "true" ]]; then
    log "Cluster:     $CLUSTER_ID (existing)"
    log "             $CLUSTER_NAME - $CLUSTER_CLOUD:$CLUSTER_REGION"
else
    log "Cluster:     $CLUSTER_NAME (new)"
    log "             $CLOUD_PROVIDER:$CLOUD_REGION ($CLUSTER_AVAILABILITY)"
fi

log "Connector:   $CONNECTOR_NAME"
log "Type:        $CONNECTOR_CLASS"
log ""

read -p "Proceed with deployment? (y/n): " PROCEED

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    log "❌ Deployment cancelled"
    rm -f terraform.tfvars
    exit 0
fi

#############################################
# Step 6: Deploy
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Step 6: Deploying Resources"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

if [[ "$USE_EXISTING_CLUSTER" == "true" ]]; then
    log "🚀 Deploying connector to existing cluster..."
    log "   (This takes 2-3 minutes)"

    # For existing cluster, we need a different approach
    # Create a minimal deployment that only creates the connector
    cat > main-connector-only.tf << 'EOFTF'
data "confluent_environment" "existing" {
  id = var.environment_id
}

data "confluent_kafka_cluster" "existing" {
  id = var.existing_cluster_id
  environment {
    id = data.confluent_environment.existing.id
  }
}

# Service Account for connectors
resource "confluent_service_account" "connector_service_account" {
  display_name = "${var.connector_configs[0].name}-sa"
  description  = "Service account for connector"
}

# API Key for the service account
resource "confluent_api_key" "connector_api_key" {
  display_name = "${var.connector_configs[0].name}-api-key"
  description  = "API Key for connector"
  owner {
    id          = confluent_service_account.connector_service_account.id
    api_version = confluent_service_account.connector_service_account.api_version
    kind        = confluent_service_account.connector_service_account.kind
  }

  managed_resource {
    id          = data.confluent_kafka_cluster.existing.id
    api_version = data.confluent_kafka_cluster.existing.api_version
    kind        = data.confluent_kafka_cluster.existing.kind

    environment {
      id = data.confluent_environment.existing.id
    }
  }
}

resource "confluent_connector" "cloud_connectors" {
  for_each = { for idx, connector in var.connector_configs : connector.name => connector }

  environment {
    id = data.confluent_environment.existing.id
  }

  kafka_cluster {
    id = data.confluent_kafka_cluster.existing.id
  }

  config_sensitive = {
    "kafka.api.key"    = confluent_api_key.connector_api_key.id
    "kafka.api.secret" = confluent_api_key.connector_api_key.secret
  }

  config_nonsensitive = merge(
    {
      "connector.class"    = each.value.connector_class
      "name"               = each.value.name
      "kafka.auth.mode"    = "KAFKA_API_KEY"
    },
    each.value.config
  )
}

output "connector_ids" {
  value = { for k, v in confluent_connector.cloud_connectors : k => v.id }
}

output "connector_status" {
  value = { for k, v in confluent_connector.cloud_connectors : k => v.status }
}
EOFTF

    # Add existing_cluster_id to terraform.tfvars
    echo "existing_cluster_id = \"$CLUSTER_ID\"" >> terraform.tfvars

    terraform apply -auto-approve \
      -target=confluent_service_account.connector_service_account \
      -target=confluent_api_key.connector_api_key \
      -target=confluent_connector.cloud_connectors
else
    log "🚀 Deploying full infrastructure..."
    log "   (This takes 3-5 minutes)"

    terraform apply -auto-approve
fi

#############################################
# Step 7: Results
#############################################

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "✅ Deployment Complete!"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

# Get outputs
if [[ "$USE_EXISTING_CLUSTER" != "true" ]]; then
    DEPLOYED_ENV_ID=$(terraform output -json 2>/dev/null | jq -r '.environment_id.value // empty')
    DEPLOYED_CLUSTER_ID=$(terraform output -json 2>/dev/null | jq -r '.cluster_id.value // empty')
    BOOTSTRAP_ENDPOINT=$(terraform output -json 2>/dev/null | jq -r '.cluster_bootstrap_endpoint.value // empty')
else
    DEPLOYED_ENV_ID=$ENVIRONMENT_ID
    DEPLOYED_CLUSTER_ID=$CLUSTER_ID
    BOOTSTRAP_ENDPOINT="N/A (existing cluster)"
fi

DEPLOYED_CONNECTOR_ID=$(terraform output -json 2>/dev/null | jq -r '.connector_ids.value | to_entries[0].value // empty')
CONNECTOR_STATUS=$(terraform output -json 2>/dev/null | jq -r '.connector_status.value | to_entries[0].value // empty')

log "📊 Deployment Details:"
log ""
log "Environment:  $DEPLOYED_ENV_ID"
log "Cluster:      $DEPLOYED_CLUSTER_ID"
if [[ "$USE_EXISTING_CLUSTER" != "true" ]]; then
    log "Bootstrap:    $BOOTSTRAP_ENDPOINT"
fi
log ""
log "Connector:    $DEPLOYED_CONNECTOR_ID"
log "Name:         $CONNECTOR_NAME"
log "Type:         $CONNECTOR_CLASS"
log "Status:       $CONNECTOR_STATUS"
log ""
log "🌐 View in Confluent Cloud:"
log "   https://confluent.cloud/environments/$DEPLOYED_ENV_ID"
log ""

# Save details
cat > .deployment_info << EOF
ENVIRONMENT_ID=$DEPLOYED_ENV_ID
CLUSTER_ID=$DEPLOYED_CLUSTER_ID
CONNECTOR_ID=$DEPLOYED_CONNECTOR_ID
CONNECTOR_NAME=$CONNECTOR_NAME
CONNECTOR_CLASS=$CONNECTOR_CLASS
EOF

log "💾 Deployment details saved to .deployment_info"
log ""
log "🎯 Next Steps:"
log "   1. View resources in Confluent Cloud UI"
log "   2. Monitor connector status"
log "   3. Test data flow"
log ""

read -p "Clean up resources now? (y/n): " CLEANUP

if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
    log ""
    log "🧹 Cleaning up resources..."
    terraform destroy -auto-approve
    rm -f terraform.tfvars .deployment_info main-connector-only.tf
    log "✅ Cleanup complete!"
else
    log ""
    log "💡 To clean up later, run:"
    log "   cd $DIR && terraform destroy"
fi

log ""
log "✅ Done!"
