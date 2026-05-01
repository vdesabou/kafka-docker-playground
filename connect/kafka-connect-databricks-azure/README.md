# Azure Databricks Sink connector

## Objective

Quickly test the [Azure Databricks Sink](https://github.com/Amitninja12345/kafka-connect-databricks-azure-) connector.

This is a self-managed Kafka Connect Sink Connector that streams data from Kafka topics directly into **Azure Databricks Delta Lake** tables using the [Databricks SQL Statement Execution REST API](https://docs.databricks.com/api/azure/workspace/statementexecution). No S3/ADLS staging is required.

### Key Features

- Writes to Delta Lake tables in Unity Catalog or legacy Hive metastore
- Auto-creates target tables from Kafka Connect record schemas
- INSERT (append) and MERGE (upsert) write modes
- Configurable batching and exponential-backoff retries
- Dynamic table name mapping via `${topic}`

## Prerequisites

- An **Azure Databricks** workspace with a running SQL Warehouse
- A Databricks **Personal Access Token (PAT)** — generate one in *User Settings > Developer > Access Tokens*
- The **SQL Warehouse ID** — found in *SQL Warehouses > your warehouse > Connection Details > HTTP path* (e.g. `/sql/1.0/warehouses/abc123`)
- Java 11+ and Maven 3.6+ installed locally (used to build the connector JAR on first run)

## How to run

Export the required environment variables, then run the script:

```bash
export DATABRICKS_WORKSPACE_URL="https://adb-123456789012.12.azuredatabricks.net"
export DATABRICKS_ACCESS_TOKEN="dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
export DATABRICKS_WAREHOUSE_ID="abc123def456"
export DATABRICKS_SCHEMA_NAME="my_schema"
# Optional — defaults to hive_metastore
export DATABRICKS_CATALOG_NAME="hive_metastore"

just use <playground run> command and search for databricks-azure-sink<use tab key to activate fzf completion>, otherwise:

bash databricks-azure-sink.sh
```

Or pass them as positional arguments:

```bash
bash databricks-azure-sink.sh \
  "https://adb-123456789012.12.azuredatabricks.net" \
  "dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  "abc123def456" \
  "my_schema"
```

## Details of what the script does

### 1. Build the connector JAR

On first run the script clones the connector source and builds an uber-JAR:

```bash
git clone https://github.com/Amitninja12345/kafka-connect-databricks-azure-.git /tmp/connector
cd /tmp/connector && mvn package -DskipTests -q
cp target/kafka-connect-databricks-azure-*-uber.jar \
   connect/connect-databricks-azure-sink/kafka-connect-databricks-azure-1.0.0-SNAPSHOT-uber.jar
```

### 2. Produce sample messages to Kafka

```bash
playground topic produce \
  --topic pageviews \
  --nb-messages 50 \
  --value '{"viewtime": %g, "userid": "User_%g", "pageid": "Page_%g"}' \
  --derive-value-schema-as JSON
```

### 3. Create the connector

```bash
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
  "databricks.table.name.format": "${topic}",
  "databricks.auto.create.table": "true",
  "databricks.insert.mode": "INSERT",
  "databricks.batch.size": "100",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF
```

### 4. Verify data in Databricks

In your Databricks workspace, open the SQL Editor and run:

```sql
SELECT * FROM hive_metastore.my_schema.pageviews LIMIT 20;
```

You should see rows with `viewtime`, `userid`, and `pageid` columns.

You can also use the [MERGE (upsert) mode](https://github.com/Amitninja12345/kafka-connect-databricks-azure-) by setting:

```json
"databricks.insert.mode": "MERGE",
"databricks.pk.fields": "viewtime"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021)
