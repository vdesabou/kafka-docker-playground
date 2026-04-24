# Interactive Connector Deployment Guide

## Overview

The interactive connector deployment script guides you through creating connectors in Confluent Cloud with zero manual configuration. It supports:

✅ **Flexible Environment Selection** - Use existing or create new  
✅ **Flexible Cluster Selection** - Use existing or create new  
✅ **Multiple Connector Types** - DatagenSource, S3, PostgreSQL, MongoDB, etc.  
✅ **Guided Configuration** - Step-by-step prompts for all settings  
✅ **Automatic Deployment** - Full Terraform automation  

---

## Quick Start

### Using Playground Command

```bash
playground run -f ccloud/terraform-cloud-connector/interactive-connector-deploy.sh
```

### Direct Execution

```bash
cd /path/to/terraform-cloud-connector
./interactive-connector-deploy.sh
```

---

## Deployment Scenarios

### Scenario 1: New Environment + New Cluster + Connector

**Best for:** Starting from scratch

**Steps:**
1. Run the script
2. Select "n" for existing environment → Enter new environment name
3. Select "n" for existing cluster → Configure cluster (cloud, region, availability)
4. Select connector type → Configure connector
5. Review and deploy

**Creates:**
- New Confluent Cloud environment
- New Kafka cluster
- New connector
- Service accounts and ACLs

---

### Scenario 2: Existing Environment + New Cluster + Connector

**Best for:** Adding a cluster to an existing environment

**Steps:**
1. Run the script
2. Select "y" for existing environment → Enter environment ID (e.g., env-12345)
3. Select "n" for existing cluster → Configure cluster
4. Select connector type → Configure connector
5. Review and deploy

**Creates:**
- New Kafka cluster in existing environment
- New connector
- Service accounts and ACLs

---

### Scenario 3: Existing Environment + Existing Cluster + Connector

**Best for:** Adding a connector to an existing cluster

**Steps:**
1. Run the script
2. Select "y" for existing environment → Enter environment ID
3. Select "y" for existing cluster → Enter cluster ID (e.g., lkc-xxxxx)
4. Select connector type → Configure connector
5. Review and deploy

**Creates:**
- Only the connector (no new infrastructure)
- Service account for connector
- API keys for connector

---

## Interactive Prompts

### Step 1: Credentials

If not already configured, you'll be prompted for:

```
API Key: [your-confluent-cloud-api-key]
API Secret: [your-confluent-cloud-api-secret]
```

**Note:** Credentials are saved to `.env` file for future use.

---

### Step 2: Environment Selection

```
Available Environments:
  [env-12345] Production
  [env-67890] Development
  [t36303] Test Environment

Use existing environment? (y/n): y
Enter Environment ID (e.g., env-xxxxx): env-12345
```

**If creating new:**
```
Enter new environment name: My New Environment
```

---

### Step 3: Cluster Selection

**For existing environment:**
```
Available Clusters in env-12345:
  [lkc-abc123] prod-cluster - AWS:us-east-1 (MULTI_ZONE)
  [lkc-def456] dev-cluster - GCP:us-central1 (SINGLE_ZONE)

Use existing cluster? (y/n): y
Enter Cluster ID (e.g., lkc-xxxxx): lkc-abc123
```

**If creating new:**
```
Cluster name [pg-connector-1714012800]: my-kafka-cluster

Select Cloud Provider:
  1) AWS
  2) GCP
  3) Azure
Choice [1]: 1

Region [us-east-1]: us-west-2

Select Availability:
  1) SINGLE_ZONE (Basic - lower cost)
  2) MULTI_ZONE (High availability)
Choice [1]: 1
```

---

### Step 4: Connector Configuration

```
Popular Connectors:
  1) DatagenSource - Generate sample data
  2) S3 Sink - Write to AWS S3
  3) S3 Source - Read from AWS S3
  4) PostgreSQL CDC Source - Database change capture
  5) MongoDB Sink - Write to MongoDB
  6) Custom - Enter connector class manually

Select connector type [1]: 1
```

#### Example: DatagenSource

```
Connector name [my-connector-1714012800]: orders-datagen
Topic name [pageviews]: orders

Datagen Templates:
  1) PAGEVIEWS
  2) ORDERS
  3) USERS
  4) CLICKSTREAM
Select template [1]: 2
```

#### Example: S3 Sink

```
S3 Bucket name: my-kafka-exports
Topics to export (comma-separated): orders,users,products
AWS Access Key ID: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key: [hidden]
```

#### Example: PostgreSQL CDC Source

```
Database hostname: postgres.example.com
Database port [5432]: 5432
Database name: myapp
Database user: postgres
Database password: [hidden]
Table include list (e.g., public.users): public.orders,public.customers
```

---

### Step 5: Review and Deploy

```
📋 Deployment Summary:

Environment: env-12345 (existing)
Cluster:     lkc-abc123 (existing)
             prod-cluster - AWS:us-east-1
Connector:   orders-datagen
Type:        DatagenSource

Proceed with deployment? (y/n): y
```

---

## Supported Connector Types

### 1. DatagenSource ✅

**Purpose:** Generate sample data for testing  
**Use Cases:** Development, testing, demos  
**Configuration:**
- Topic name
- Data template (PAGEVIEWS, ORDERS, USERS, CLICKSTREAM)
- Output format (JSON)

**Example:**
```
Topic: test-orders
Template: ORDERS
Format: JSON
Tasks: 1
```

---

### 2. S3 Sink ✅

**Purpose:** Export Kafka topics to AWS S3  
**Use Cases:** Data lake, long-term storage, analytics  
**Configuration:**
- S3 bucket name
- Topics to export
- AWS credentials
- Format (JSON)

**Example:**
```
Bucket: my-data-lake
Topics: orders,users
Region: us-east-1
```

---

### 3. S3 Source ✅

**Purpose:** Import data from S3 to Kafka  
**Use Cases:** Data ingestion, batch processing  
**Configuration:**
- S3 bucket name
- Target topic
- AWS credentials
- Format (JSON)

**Example:**
```
Bucket: incoming-data
Topic: raw-events
Region: us-east-1
```

---

### 4. PostgreSQL CDC Source ✅

**Purpose:** Capture database changes in real-time  
**Use Cases:** Event sourcing, data synchronization, microservices  
**Configuration:**
- Database connection details
- Table selection
- Replication settings

**Example:**
```
Host: postgres.internal
Port: 5432
Database: production
Tables: public.orders,public.inventory
```

---

### 5. MongoDB Sink ✅

**Purpose:** Write Kafka data to MongoDB  
**Use Cases:** Document store, aggregation, caching  
**Configuration:**
- MongoDB connection URI
- Database name
- Topics to sync

**Example:**
```
URI: mongodb+srv://cluster.mongodb.net
Database: analytics
Topics: events,metrics
```

---

### 6. Custom Connector ✅

**Purpose:** Any other Confluent Cloud connector  
**Configuration:**
- Connector class name
- Custom JSON configuration

**Example:**
```
Connector class: BigQuerySink
Configuration: {
  "project": "my-gcp-project",
  "dataset": "kafka_data",
  ...
}
```

---

## Deployment Output

### Success Example

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Deployment Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Deployment Details:

Environment:  env-12345
Cluster:      lkc-abc123
Bootstrap:    SASL_SSL://pkc-xxxxx.us-east-1.aws.confluent.cloud:9092

Connector:    lcc-xyz789
Name:         orders-datagen
Type:         DatagenSource
Status:       RUNNING

🌐 View in Confluent Cloud:
   https://confluent.cloud/environments/env-12345

💾 Deployment details saved to .deployment_info
```

---

## Post-Deployment

### View Connector Status

```bash
# In Confluent Cloud UI
https://confluent.cloud/environments/<env-id>/clusters/<cluster-id>/connectors/<connector-id>

# Or using CLI
confluent connector describe <connector-id> --environment <env-id> --cluster <cluster-id>
```

### Test Data Flow

**For DatagenSource:**
```bash
# Consume messages to verify data is flowing
kafka-console-consumer \
  --bootstrap-server <bootstrap-endpoint> \
  --topic <topic-name> \
  --from-beginning \
  --max-messages 10
```

**For Sink Connectors:**
```bash
# Produce test messages
kafka-console-producer \
  --bootstrap-server <bootstrap-endpoint> \
  --topic <topic-name>

# Verify data in destination (S3, MongoDB, etc.)
```

---

## Cleanup

### During Deployment

At the end of deployment, you'll be prompted:

```
Clean up resources now? (y/n): y
```

**If yes:** All resources are immediately destroyed  
**If no:** Resources remain active (you can delete later)

### Manual Cleanup

```bash
cd /path/to/terraform-cloud-connector
terraform destroy -auto-approve
```

**What gets deleted:**
- Connector(s)
- Service accounts
- API keys
- Kafka cluster (if created by script)
- Environment (if created by script)

**What stays:**
- Existing environments (not managed by script)
- Existing clusters (not managed by script)

---

## Saved Files

### .env
Contains your Confluent Cloud credentials:
```bash
export CONFLUENT_CLOUD_API_KEY="..."
export CONFLUENT_CLOUD_API_SECRET="..."
```

### terraform.tfvars
Contains deployment configuration:
```hcl
confluent_cloud_api_key = "..."
use_existing_environment = true
environment_id = "env-12345"
cluster_name = "my-cluster"
connector_configs = [...]
```

### .deployment_info
Contains deployment details:
```bash
ENVIRONMENT_ID=env-12345
CLUSTER_ID=lkc-abc123
CONNECTOR_ID=lcc-xyz789
CONNECTOR_NAME=orders-datagen
CONNECTOR_CLASS=DatagenSource
```

---

## Troubleshooting

### Issue: "Environment not found"

**Cause:** Invalid environment ID  
**Solution:** List available environments:
```bash
curl -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  https://api.confluent.cloud/org/v2/environments
```

### Issue: "Cluster not found"

**Cause:** Invalid cluster ID or cluster not in selected environment  
**Solution:** List clusters in environment:
```bash
curl -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  "https://api.confluent.cloud/cmk/v2/clusters?environment=<env-id>"
```

### Issue: "403 Forbidden"

**Cause:** API key lacks permissions  
**Solution:** Use Cloud API key with OrganizationAdmin or EnvironmentAdmin role

### Issue: "Connector failed to start"

**Cause:** Invalid connector configuration  
**Solution:** 
1. Check connector logs in Confluent Cloud UI
2. Verify credentials (AWS keys, database passwords, etc.)
3. Ensure network connectivity from Confluent Cloud to external systems

---

## Best Practices

### 1. Use Existing Infrastructure When Possible

- ✅ Reuse environments to avoid hitting limits
- ✅ Reuse clusters to reduce costs
- ✅ Only create new resources when necessary

### 2. Choose Appropriate Cluster Settings

- **Development:** SINGLE_ZONE, Basic tier
- **Production:** MULTI_ZONE, Standard/Dedicated tier
- **Testing:** SINGLE_ZONE, Basic tier (delete after testing)

### 3. Secure Credentials

- ✅ Use `.env` file (excluded from git)
- ✅ Restrict API key permissions
- ✅ Rotate credentials regularly
- ❌ Don't commit credentials to git

### 4. Clean Up Test Resources

- ✅ Delete test connectors after validation
- ✅ Remove unused clusters to avoid charges
- ✅ Keep environments organized

### 5. Monitor Costs

- ✅ Review cluster usage in Confluent Cloud
- ✅ Right-size connectors (tasks.max)
- ✅ Delete idle resources

---

## Advanced Usage

### Batch Deployments

Deploy multiple connectors sequentially:

```bash
# Deploy first connector
./interactive-connector-deploy.sh
# Select existing cluster, create connector 1

# Deploy second connector  
./interactive-connector-deploy.sh
# Select same existing cluster, create connector 2

# etc...
```

### Custom Connector Configuration

For advanced connectors, select option 6 (Custom) and provide full JSON:

```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://host:5432/db",
  "connection.user": "user",
  "connection.password": "password",
  "mode": "incrementing",
  "incrementing.column.name": "id",
  "topic.prefix": "jdbc-"
}
```

---

## Examples

### Example 1: Quick Test with DatagenSource

```bash
$ ./interactive-connector-deploy.sh

# Prompts:
Use existing environment? y
Enter Environment ID: env-12345
Use existing cluster? y  
Enter Cluster ID: lkc-abc123
Select connector type: 1 (DatagenSource)
Connector name: test-datagen
Topic name: test-topic
Select template: 1 (PAGEVIEWS)
Proceed? y

# Result: Connector running in ~2 minutes
```

### Example 2: Production S3 Sink

```bash
$ ./interactive-connector-deploy.sh

# Prompts:
Use existing environment? y
Enter Environment ID: env-prod
Use existing cluster? y
Enter Cluster ID: lkc-prod-01
Select connector type: 2 (S3 Sink)
S3 Bucket: prod-kafka-archive
Topics: orders,transactions,events
AWS Access Key: AKIA...
Proceed? y

# Result: Data flowing to S3 in ~3 minutes
```

### Example 3: New Environment from Scratch

```bash
$ ./interactive-connector-deploy.sh

# Prompts:
Use existing environment? n
Environment name: Development
Use existing cluster? n
Cluster name: dev-cluster
Cloud: 1 (AWS)
Region: us-west-2
Availability: 1 (SINGLE_ZONE)
Connector type: 1 (DatagenSource)
Proceed? y

# Result: Full environment + cluster + connector in ~5 minutes
```

---

## Summary

The interactive connector deployment script provides a **user-friendly way** to deploy connectors to Confluent Cloud with:

✅ **No manual configuration files**  
✅ **Intelligent defaults**  
✅ **Environment/cluster reuse**  
✅ **Multiple connector types**  
✅ **Automatic cleanup options**  

**Perfect for:**
- Quick testing
- POC/demos
- Learning Confluent Cloud
- Production deployments with guidance

**Happy connecting!** 🚀
