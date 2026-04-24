#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Playground Auto Connector - Universal
#
# Deploy ANY Confluent Cloud connector with automation
#
# Usage:
#   playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector S3_SINK
#   playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector MONGODB_SINK
#   playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector POSTGRES_SOURCE
#############################################

# Parse arguments
CONNECTOR_TYPE=""
CONNECTOR_CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --connector) CONNECTOR_TYPE="$2"; shift 2;;
        --config) CONNECTOR_CONFIG="$2"; shift 2;;
        *) shift;;
    esac
done

if [ -z "$CONNECTOR_TYPE" ]; then
    log "🔌 Available Connector Categories:"
    log ""
    log "AWS Connectors:"
    log "  S3_SINK, S3_SOURCE, KINESIS_SOURCE, KINESIS_SINK"
    log "  LAMBDA_SINK, DYNAMODB_SINK, SQS_SOURCE, REDSHIFT_SINK"
    log ""
    log "GCP Connectors:"
    log "  GCS_SINK, GCS_SOURCE, BIGQUERY_SINK, PUBSUB_SOURCE, PUBSUB_SINK"
    log ""
    log "Azure Connectors:"
    log "  AZURE_BLOB_STORAGE_SINK, AZURE_BLOB_STORAGE_SOURCE"
    log "  AZURE_EVENT_HUBS_SOURCE, AZURE_SQL_SINK"
    log ""
    log "Database Connectors:"
    log "  POSTGRES_SOURCE, POSTGRES_SINK, MYSQL_SOURCE, MYSQL_SINK"
    log "  ORACLE_DATABASE_SOURCE, SQL_SERVER_SOURCE"
    log ""
    log "NoSQL Connectors:"
    log "  MONGODB_SOURCE, MONGODB_SINK, CASSANDRA_SINK"
    log "  ELASTICSEARCH_SINK, REDIS_SINK"
    log ""
    log "Others:"
    log "  HTTP_SINK, DATAGEN, SALESFORCE_SOURCE, SNOWFLAKE_SINK"
    log ""
    read -p "Enter connector type: " CONNECTOR_TYPE
fi

CONNECTOR_TYPE=$(echo "$CONNECTOR_TYPE" | tr '[:lower:]' '[:upper:]')

log "🚀 Deploying $CONNECTOR_TYPE Connector"
log "========================================"

# Auto-setup
if ! command -v terraform &> /dev/null; then
    log "📦 Installing Terraform..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew tap hashicorp/tap && brew install hashicorp/tap/terraform
    else
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform jq
    fi
fi

# Check credentials
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    if [ -f "$DIR/.env" ]; then
        source "$DIR/.env"
    else
        log ""
        log "⚠️  Confluent Cloud credentials:"
        read -p "API Key: " CONFLUENT_CLOUD_API_KEY
        read -s -p "API Secret: " CONFLUENT_CLOUD_API_SECRET
        echo ""
        export CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    fi
fi

# Check cloud-specific credentials
case $CONNECTOR_TYPE in
    *S3*|*KINESIS*|*LAMBDA*|*DYNAMODB*|*SQS*|*REDSHIFT*)
        if [ -z "$AWS_ACCESS_KEY_ID" ]; then
            log ""
            log "⚠️  AWS credentials needed:"
            read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
            read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
            echo ""
            export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        fi
        ;;
    *GCS*|*BIGQUERY*|*PUBSUB*)
        if [ -z "$GCP_PROJECT_ID" ]; then
            log ""
            log "⚠️  GCP credentials needed:"
            read -p "GCP Project ID: " GCP_PROJECT_ID
            read -p "GCP Service Account Key (path): " GCP_SA_KEY
            export GCP_PROJECT_ID GCP_SA_KEY
        fi
        ;;
    *AZURE*)
        if [ -z "$AZURE_STORAGE_ACCOUNT" ]; then
            log ""
            log "⚠️  Azure credentials needed:"
            read -p "Azure Storage Account: " AZURE_STORAGE_ACCOUNT
            read -s -p "Azure Storage Key: " AZURE_STORAGE_KEY
            echo ""
            export AZURE_STORAGE_ACCOUNT AZURE_STORAGE_KEY
        fi
        ;;
esac

cd "$DIR"

# Initialize Terraform
if [ ! -d ".terraform" ]; then
    terraform init
fi

# Generate connector config based on type
CLUSTER_NAME="pg-auto-${CONNECTOR_TYPE,,}-${USER}"
TOPIC_NAME="test_topic"

log ""
log "📝 Generating $CONNECTOR_TYPE configuration..."

# Use provided config or generate default
if [ -n "$CONNECTOR_CONFIG" ] && [ -f "$CONNECTOR_CONFIG" ]; then
    CONNECTOR_JSON=$(cat "$CONNECTOR_CONFIG")
else
    # Generate default config based on connector type
    case $CONNECTOR_TYPE in
        DATAGEN)
            read -p "Topic name [pageviews]: " TOPIC_NAME
            TOPIC_NAME=${TOPIC_NAME:-pageviews}
            CONNECTOR_JSON=$(cat <<EOF
{
  "kafka.topic": "$TOPIC_NAME",
  "quickstart": "PAGEVIEWS",
  "output.data.format": "JSON",
  "tasks.max": "1"
}
EOF
)
            ;;
        S3_SINK)
            read -p "S3 Bucket: " S3_BUCKET
            CONNECTOR_JSON=$(cat <<EOF
{
  "topics": "$TOPIC_NAME",
  "input.data.format": "JSON",
  "s3.bucket.name": "$S3_BUCKET",
  "s3.region": "${AWS_REGION:-us-east-1}",
  "output.data.format": "JSON",
  "time.interval": "HOURLY",
  "flush.size": "1000",
  "tasks.max": "1",
  "aws.access.key.id": "$AWS_ACCESS_KEY_ID",
  "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY"
}
EOF
)
            ;;
        MONGODB_SINK)
            read -p "MongoDB Connection String: " MONGO_URI
            read -p "Database name: " MONGO_DB
            CONNECTOR_JSON=$(cat <<EOF
{
  "topics": "$TOPIC_NAME",
  "input.data.format": "JSON",
  "connection.uri": "$MONGO_URI",
  "database": "$MONGO_DB",
  "tasks.max": "1"
}
EOF
)
            ;;
        POSTGRES_SINK)
            read -p "Postgres Host: " PG_HOST
            read -p "Database: " PG_DB
            read -p "User: " PG_USER
            read -s -p "Password: " PG_PASS
            echo ""
            CONNECTOR_JSON=$(cat <<EOF
{
  "topics": "$TOPIC_NAME",
  "input.data.format": "JSON",
  "connection.host": "$PG_HOST",
  "connection.port": "5432",
  "connection.user": "$PG_USER",
  "connection.password": "$PG_PASS",
  "db.name": "$PG_DB",
  "tasks.max": "1"
}
EOF
)
            ;;
        *)
            logerror "Please provide config file for $CONNECTOR_TYPE"
            log "Example: playground run -f playground-auto-connector.sh -- --connector $CONNECTOR_TYPE --config examples/${CONNECTOR_TYPE,,}.json"
            exit 1
            ;;
    esac
fi

# Create Terraform config
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
environment_name           = "pg-auto-env-${USER}"
cluster_name               = "$CLUSTER_NAME"
cloud_provider             = "AWS"
cloud_region               = "${AWS_REGION:-us-east-1}"

connector_configs = [
  {
    name             = "${CONNECTOR_TYPE}_${USER}"
    connector_class  = "$CONNECTOR_TYPE"
    kafka_api_key    = "$CONFLUENT_CLOUD_API_KEY"
    kafka_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
    config = $CONNECTOR_JSON
  }
]
EOF

log ""
log "🏗️  Deploying infrastructure..."
terraform apply -auto-approve

# Get outputs
CLUSTER_ID=$(terraform output -json | jq -r '.cluster_id.value')
ENVIRONMENT_ID=$(terraform output -json | jq -r '.environment_id.value')
CONNECTOR_ID=$(terraform output -json | jq -r '.connector_ids.value | to_entries[0].value // empty')

log ""
log "╔════════════════════════════════════════════════════════╗"
log "║  $CONNECTOR_TYPE Deployed! 🎉"
log "╚════════════════════════════════════════════════════════╝"
log ""
log "📊 Details:"
log "   Environment: $ENVIRONMENT_ID"
log "   Cluster:     $CLUSTER_ID"
log "   Connector:   $CONNECTOR_ID"
log ""

# Save environment
cat > .ccloud_env << ENVEOF
export CLUSTER_ID="$CLUSTER_ID"
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export CLOUD_KEY="$(terraform output -json | jq -r '.api_key_id.value')"
export CLOUD_SECRET="$(terraform output -json | jq -r '.api_key_secret.value')"
export BOOTSTRAP_SERVERS="$(terraform output -json | jq -r '.cluster_bootstrap_endpoint.value')"
ENVEOF

source .ccloud_env

log "⏳ Waiting for connector (30 seconds)..."
sleep 30

set +e
playground connector status --connector "${CONNECTOR_TYPE}_${USER}" 2>/dev/null
set -e

log ""
log "🎯 Next Steps:"
log "   View: https://confluent.cloud/environments/$ENVIRONMENT_ID"
log "   Commands: source $DIR/.ccloud_env && playground connector list"
log ""

log "Delete infrastructure?"
check_if_continue

terraform destroy -auto-approve
rm -f terraform.tfvars .ccloud_env

log "✅ Cleanup complete!"
