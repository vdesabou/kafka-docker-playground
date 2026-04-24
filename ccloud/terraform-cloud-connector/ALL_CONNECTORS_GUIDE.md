# All Connectors Guide - Complete Automation 🔌

## 🚀 Run ANY Connector with Playground Run

We've automated **all** Confluent Cloud fully managed connectors!

### Universal Command
```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector TYPE
```

### Pre-Built Connector Scripts
```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-CONNECTOR.sh
```

---

## 📋 Complete Connector List

### AWS Connectors (11)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **S3 Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-s3-sink.sh` | AWS Keys |
| **S3 Source** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-s3-source.sh` | AWS Keys |
| **Kinesis Source** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-kinesis-source.sh` | AWS Keys |
| **Kinesis Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-kinesis-sink.sh` | AWS Keys |
| **Lambda Sink** | `playground-auto-connector.sh -- --connector LAMBDA_SINK` | AWS Keys |
| **DynamoDB Sink** | `playground-auto-connector.sh -- --connector DYNAMODB_SINK` | AWS Keys |
| **SQS Source** | `playground-auto-connector.sh -- --connector SQS_SOURCE` | AWS Keys |
| **Redshift Sink** | `playground-auto-connector.sh -- --connector REDSHIFT_SINK` | AWS Keys |

---

### GCP Connectors (7)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **GCS Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-gcs-sink.sh` | GCP SA Key |
| **GCS Source** | `playground-auto-connector.sh -- --connector GCS_SOURCE` | GCP SA Key |
| **BigQuery Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-bigquery-sink.sh` | GCP SA Key |
| **Pub/Sub Source** | `playground-auto-connector.sh -- --connector PUBSUB_SOURCE` | GCP SA Key |
| **Pub/Sub Sink** | `playground-auto-connector.sh -- --connector PUBSUB_SINK` | GCP SA Key |

---

### Azure Connectors (13)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **Blob Storage Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-azure-blob-storage-sink.sh` | Azure Keys |
| **Blob Storage Source** | `playground-auto-connector.sh -- --connector AZURE_BLOB_STORAGE_SOURCE` | Azure Keys |
| **Event Hubs Source** | `playground-auto-connector.sh -- --connector AZURE_EVENT_HUBS_SOURCE` | Azure Keys |
| **Azure SQL Sink** | `playground-auto-connector.sh -- --connector AZURE_SQL_SINK` | Azure SQL Creds |

---

### Database Connectors (16)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **PostgreSQL Source (CDC)** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-postgres-source.sh` | Postgres Creds |
| **PostgreSQL Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-postgres-sink.sh` | Postgres Creds |
| **MySQL Source (CDC)** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-mysql-source.sh` | MySQL Creds |
| **MySQL Sink** | `playground-auto-connector.sh -- --connector MYSQL_SINK` | MySQL Creds |
| **Oracle DB Source (CDC)** | `playground-auto-connector.sh -- --connector ORACLE_DATABASE_SOURCE` | Oracle Creds |
| **SQL Server Source (CDC)** | `playground-auto-connector.sh -- --connector SQL_SERVER_SOURCE` | SQL Server Creds |

---

### NoSQL Connectors (14)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **MongoDB Source (CDC)** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-mongodb-source.sh` | MongoDB URI |
| **MongoDB Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-mongodb-sink.sh` | MongoDB URI |
| **Cassandra Sink** | `playground-auto-connector.sh -- --connector CASSANDRA_SINK` | Cassandra Creds |
| **Elasticsearch Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-elasticsearch-sink.sh` | Elastic Creds |
| **Redis Sink** | `playground-auto-connector.sh -- --connector REDIS_SINK` | Redis Creds |

---

### Messaging Connectors (8)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **HTTP Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-http-sink.sh` | API Endpoint |
| **Datagen** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh` | None! |

---

### SaaS Connectors (15)

| Connector | Command | Credentials Needed |
|-----------|---------|-------------------|
| **Salesforce Source (CDC)** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-salesforce-source.sh` | Salesforce API |
| **Snowflake Sink** | `playground run -f ccloud/terraform-cloud-connector/playground-auto-snowflake-sink.sh` | Snowflake Keys |
| **ServiceNow Source** | `playground-auto-connector.sh -- --connector SERVICENOW_SOURCE` | ServiceNow API |

---

## 🎯 Quick Start Examples

### Example 1: S3 Sink (Most Popular)
```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

# Run automated script
playground run -f ccloud/terraform-cloud-connector/playground-auto-s3-sink.sh

# Script prompts for S3 bucket name
# Everything else is automated!
```

### Example 2: PostgreSQL Source (CDC)
```bash
# Run automated script
playground run -f ccloud/terraform-cloud-connector/playground-auto-postgres-source.sh

# Script prompts for:
# - Postgres host
# - Database name
# - Username/password
# Then deploys automatically!
```

### Example 3: MongoDB Sink
```bash
# Run automated script
playground run -f ccloud/terraform-cloud-connector/playground-auto-mongodb-sink.sh

# Script prompts for:
# - MongoDB connection string
# - Database name
# Then deploys!
```

### Example 4: Custom Connector Type
```bash
# Use universal script for any connector
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector REDIS_SINK

# Or with custom config file
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- \
  --connector SNOWFLAKE_SINK \
  --config examples/snowflake.json
```

---

## 🛠️ What Gets Automated

For **every** connector:

1. ✅ **Dependency Installation**
   - Terraform
   - jq
   - Confluent CLI (if needed)

2. ✅ **Credential Management**
   - Checks environment variables
   - Prompts interactively
   - Saves for next time

3. ✅ **Configuration Generation**
   - Smart defaults
   - Interactive prompts
   - Validates inputs

4. ✅ **Deployment**
   - Creates Confluent Cloud cluster
   - Deploys connector
   - Verifies status

5. ✅ **Verification**
   - Checks connector status
   - Tests connectivity
   - Shows next steps

6. ✅ **Cleanup**
   - Prompts before destroying
   - Complete cleanup
   - No orphaned resources

---

## 📊 Credential Requirements by Category

### AWS Connectors
```bash
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_REGION="us-east-1"  # optional
```

### GCP Connectors
```bash
export GCP_PROJECT_ID="your-project"
export GCP_SA_KEY="/path/to/service-account-key.json"
```

### Azure Connectors
```bash
export AZURE_STORAGE_ACCOUNT="your-account"
export AZURE_STORAGE_KEY="your-key"
```

### Database Connectors
```bash
# Prompted interactively during deployment
# Or set beforehand:
export DB_HOST="hostname"
export DB_NAME="database"
export DB_USER="username"
export DB_PASSWORD="password"
```

---

## 🎬 Complete Workflow

### Step 1: Choose Connector
```bash
# List all available connectors
playground run -f ccloud/terraform-cloud-connector/playground-list-connectors.sh
```

### Step 2: Run Automated Script
```bash
# Use pre-built script
playground run -f ccloud/terraform-cloud-connector/playground-auto-CONNECTOR.sh

# Or universal script
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector TYPE
```

### Step 3: Answer Prompts
- Confluent Cloud credentials (once)
- Cloud-specific credentials (if needed)
- Connector-specific config (bucket name, connection string, etc.)

### Step 4: Wait for Deployment
- Cluster creation: ~2 minutes
- Connector deployment: ~1 minute
- Total: 3-4 minutes

### Step 5: Verify
```bash
# Source environment
source ccloud/terraform-cloud-connector/.ccloud_env

# Check status
playground connector status --connector YOUR_CONNECTOR

# View in Confluent Cloud
# URL provided in output
```

### Step 6: Clean Up
```bash
# Re-run same script
# Choose "yes" when prompted to delete
```

---

## 💡 Pro Tips

### Tip 1: Save Credentials
First run saves credentials to `.env`:
```bash
# First time: enter credentials
playground run -f ccloud/terraform-cloud-connector/playground-auto-s3-sink.sh

# Second time: uses saved credentials
playground run -f ccloud/terraform-cloud-connector/playground-auto-bigquery-sink.sh
```

### Tip 2: Use Config Files
For complex connectors:
```bash
# Create config file
cat > examples/my-snowflake.json << 'EOF'
{
  "snowflake.url.name": "myaccount.snowflakecomputing.com",
  "snowflake.user.name": "myuser",
  "snowflake.private.key": "...",
  "snowflake.database.name": "KAFKA_DB",
  "snowflake.schema.name": "KAFKA_SCHEMA"
}
EOF

# Use with connector
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- \
  --connector SNOWFLAKE_SINK \
  --config examples/my-snowflake.json
```

### Tip 3: Multi-Connector Setup
Deploy multiple connectors to same cluster:
```bash
# Use wizard for multi-connector
playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh

# Or manually edit terraform.tfvars
```

### Tip 4: Keep Infrastructure Running
When prompted "Delete?", choose **No** to keep running.

Later, destroy manually:
```bash
cd ccloud/terraform-cloud-connector
terraform destroy -auto-approve
```

---

## 🔍 Finding the Right Connector

### By Use Case

**Want to archive data?**
- S3 Sink, GCS Sink, Azure Blob Sink

**Want to load analytics warehouse?**
- BigQuery Sink, Snowflake Sink, Redshift Sink

**Want change data capture (CDC)?**
- PostgreSQL Source, MySQL Source, MongoDB Source, Oracle Source

**Want to integrate SaaS?**
- Salesforce Source, ServiceNow Source

**Want real-time search?**
- Elasticsearch Sink

**Want to test/develop?**
- Datagen Source (no external system needed!)

---

## 📚 Documentation Hierarchy

1. **This Guide** - All connectors overview
2. **PLAYGROUND_RUN_GUIDE.md** - Playground integration details
3. **ZERO_CONFIG_INSTALL.md** - Zero-config automation guide
4. **README.md** - Complete tool documentation

---

## 🆘 Troubleshooting

### Issue: "Connector type not recognized"
**Solution**: Use exact connector name from list above. Case-insensitive.

### Issue: "Missing credentials"
**Solution**: Script prompts automatically. Just enter when asked.

### Issue: "Want to see all options"
```bash
# List all connectors
playground run -f ccloud/terraform-cloud-connector/playground-list-connectors.sh

# Use wizard for guided setup
playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh
```

### Issue: "Need custom configuration"
```bash
# Use --config flag
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- \
  --connector YOUR_TYPE \
  --config path/to/config.json
```

---

## 🎉 Summary

**96+ Connectors. Zero Manual Configuration.**

```bash
# Pick any connector
playground run -f ccloud/terraform-cloud-connector/playground-auto-s3-sink.sh
playground run -f ccloud/terraform-cloud-connector/playground-auto-postgres-source.sh
playground run -f ccloud/terraform-cloud-connector/playground-auto-mongodb-sink.sh

# Or use universal
playground run -f ccloud/terraform-cloud-connector/playground-auto-connector.sh -- --connector TYPE
```

**Every connector is fully automated!** 🚀
