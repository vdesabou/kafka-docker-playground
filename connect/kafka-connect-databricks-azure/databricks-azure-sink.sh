#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

DATABRICKS_WORKSPACE_URL=${DATABRICKS_WORKSPACE_URL:-$1}
DATABRICKS_ACCESS_TOKEN=${DATABRICKS_ACCESS_TOKEN:-$2}
DATABRICKS_WAREHOUSE_ID=${DATABRICKS_WAREHOUSE_ID:-$3}
DATABRICKS_SCHEMA_NAME=${DATABRICKS_SCHEMA_NAME:-$4}
DATABRICKS_CATALOG_NAME=${DATABRICKS_CATALOG_NAME:-"hive_metastore"}

if [ -z "$DATABRICKS_WORKSPACE_URL" ]
then
     logerror "DATABRICKS_WORKSPACE_URL is not set. Export it as environment variable or pass it as argument"
     logerror "Example: https://adb-123456789012.12.azuredatabricks.net"
     exit 1
fi

if [ -z "$DATABRICKS_ACCESS_TOKEN" ]
then
     logerror "DATABRICKS_ACCESS_TOKEN is not set. Export it as environment variable or pass it as argument"
     logerror "Generate a PAT in Databricks: User Settings > Developer > Access Tokens"
     exit 1
fi

if [ -z "$DATABRICKS_WAREHOUSE_ID" ]
then
     logerror "DATABRICKS_WAREHOUSE_ID is not set. Export it as environment variable or pass it as argument"
     logerror "Found in Databricks SQL Warehouse > Connection Details > HTTP path"
     exit 1
fi

if [ -z "$DATABRICKS_SCHEMA_NAME" ]
then
     logerror "DATABRICKS_SCHEMA_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# Build the connector uber-JAR if not present
CONNECTOR_JAR="${DIR}/kafka-connect-databricks-azure-1.0.0-SNAPSHOT-uber.jar"
if [ ! -f "$CONNECTOR_JAR" ]
then
     log "Building kafka-connect-databricks-azure connector uber-JAR..."
     tmpdir=$(mktemp -d)
     git clone https://github.com/Amitninja12345/kafka-connect-databricks-azure-.git "$tmpdir"
     cd "$tmpdir"
     mvn package -DskipTests -q
     cp target/kafka-connect-databricks-azure-*-uber.jar "$CONNECTOR_JAR"
     cd -
     rm -rf "$tmpdir"
     log "Connector JAR built successfully: $CONNECTOR_JAR"
fi

# Install connector plugin into the confluent-hub components directory
PLUGIN_DIR="../../confluent-hub/amitninja-kafka-connect-databricks-azure/lib"
mkdir -p "$PLUGIN_DIR"
cp "$CONNECTOR_JAR" "$PLUGIN_DIR/kafka-connect-databricks-azure-uber.jar"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic pageviews"
playground topic produce \
     --topic pageviews \
     --nb-messages 50 \
     --value '{"viewtime": %g, "userid": "User_%g", "pageid": "Page_%g"}' \
     --value-schema '{
          "type": "record",
          "name": "pageviews",
          "fields": [
               {"name": "viewtime", "type": "long"},
               {"name": "userid",   "type": "string"},
               {"name": "pageid",   "type": "string"}
          ]
     }' \
     --derive-value-schema-as JSON

log "Creating Azure Databricks Sink connector"
playground connector create-or-update --connector databricks-azure-sink << EOF
{
     "connector.class": "com.amitninja.connect.databricks.azure.DatabricksAzureSinkConnector",
     "tasks.max": "1",
     "topics": "pageviews",
     "databricks.workspace.url": "$DATABRICKS_WORKSPACE_URL",
     "databricks.access.token": "$DATABRICKS_ACCESS_TOKEN",
     "databricks.warehouse.id": "$DATABRICKS_WAREHOUSE_ID",
     "databricks.catalog.name": "$DATABRICKS_CATALOG_NAME",
     "databricks.schema.name": "$DATABRICKS_SCHEMA_NAME",
     "databricks.table.name.format": "\${topic}",
     "databricks.auto.create.table": "true",
     "databricks.insert.mode": "INSERT",
     "databricks.batch.size": "100",
     "databricks.max.retries": "3",
     "databricks.retry.backoff.ms": "3000",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF

playground connector show-lag --max-wait 120
