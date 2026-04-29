#!/bin/bash
set -e

#############################################
# Generate Playground Scripts for All Connectors
#
# Creates individual playground-compatible scripts
# for each connector category
#############################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🔧 Generating playground scripts for all connector types..."

# Create master connector list script
cat > "$DIR/playground-list-connectors.sh" << 'LISTEOF'
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "🔌 Confluent Cloud Fully Managed Connectors"
log "==========================================="
log ""
log "Run any connector with:"
log "  playground run -f ccloud/terraform-cloud-connector/playground-auto-{connector}.sh"
log ""
log "Or use the universal script:"
log "  playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector TYPE"
log ""
log "Available Connectors:"
log ""
LISTEOF

# Add AWS category
cat >> "$DIR/playground-list-connectors.sh" << 'EOF'
log "AWS Connectors:"
log "  playground-auto-s3-sink.sh          - Stream to S3"
log "  playground-auto-s3-source.sh        - Read from S3"
log "  playground-auto-kinesis-source.sh   - Kinesis source"
log "  playground-auto-kinesis-sink.sh     - Kinesis sink"
log "  playground-auto-lambda-sink.sh      - Lambda sink"
log "  playground-auto-dynamodb-sink.sh    - DynamoDB sink"
log ""
log "GCP Connectors:"
log "  playground-auto-gcs-sink.sh         - Cloud Storage sink"
log "  playground-auto-bigquery-sink.sh    - BigQuery sink"
log "  playground-auto-pubsub-source.sh    - Pub/Sub source"
log ""
log "Azure Connectors:"
log "  playground-auto-azure-blob-sink.sh  - Blob Storage sink"
log "  playground-auto-azure-eventhubs-source.sh - Event Hubs source"
log ""
log "Database Connectors:"
log "  playground-auto-postgres-source.sh  - PostgreSQL CDC source"
log "  playground-auto-postgres-sink.sh    - PostgreSQL sink"
log "  playground-auto-mysql-source.sh     - MySQL CDC source"
log "  playground-auto-mongodb-sink.sh     - MongoDB sink"
log ""
log "NoSQL Connectors:"
log "  playground-auto-elasticsearch-sink.sh - Elasticsearch sink"
log "  playground-auto-redis-sink.sh       - Redis sink"
log ""
log "Other Connectors:"
log "  playground-auto-http-sink.sh        - HTTP sink"
log "  playground-auto-snowflake-sink.sh   - Snowflake sink"
log "  playground-auto-salesforce-source.sh - Salesforce CDC source"
log ""
log "📚 Documentation:"
log "  See PLAYGROUND_RUN_GUIDE.md for details"
EOF

chmod +x "$DIR/playground-list-connectors.sh"

# Generate wrapper scripts for popular connectors
generate_wrapper() {
    local connector_type=$1
    local connector_name=$(echo "$connector_type" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    local script_name="playground-auto-${connector_name}.sh"

    cat > "$DIR/$script_name" << EOF
#!/bin/bash
set -e

DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Run universal connector script with this connector type
bash "\$DIR/playground-auto-connector.sh" --connector $connector_type "\$@"
EOF

    chmod +x "$DIR/$script_name"
    log "  Created $script_name"
}

log ""
log "Generating wrapper scripts..."

# Generate wrappers for key connectors
KEY_CONNECTORS=(
    "S3_SINK"
    "S3_SOURCE"
    "KINESIS_SOURCE"
    "GCS_SINK"
    "BIGQUERY_SINK"
    "AZURE_BLOB_STORAGE_SINK"
    "POSTGRES_SOURCE"
    "POSTGRES_SINK"
    "MYSQL_SOURCE"
    "MONGODB_SOURCE"
    "MONGODB_SINK"
    "ELASTICSEARCH_SINK"
    "HTTP_SINK"
    "SNOWFLAKE_SINK"
    "SALESFORCE_SOURCE"
)

for connector in "${KEY_CONNECTORS[@]}"; do
    generate_wrapper "$connector"
done

log ""
log "✅ Generated $(ls -1 "$DIR"/playground-auto-*.sh | wc -l) playground scripts"
log ""
log "📋 Usage:"
log "  playground run -f ccloud/terraform-cloud-connector/playground-auto-s3-sink.sh"
log "  playground run -f ccloud/terraform-cloud-connector/playground-auto-postgres-source.sh"
log "  playground run -f ccloud/terraform-cloud-connector/playground-list-connectors.sh"
log ""
log "Or use the universal script:"
log "  playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector MONGODB_SINK"
