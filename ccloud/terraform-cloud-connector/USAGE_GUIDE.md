# Usage Guide - deploy-connector.sh

## Quick Start

```bash
cd ccloud/terraform-cloud-connector
./deploy-connector.sh
```

The script will interactively guide you through all steps!

---

## What You'll Be Asked

### Step 1: Confluent Cloud Credentials

```
Confluent Cloud API Key: [enter your key]
Confluent Cloud API Secret: [hidden]
```

**Where to get credentials:**
1. Go to https://confluent.cloud
2. Navigate to: Administration → Cloud API Keys
3. Click "Add Key"
4. Copy the API Key and Secret

**Note:** Credentials are saved to `.env` file and reused on subsequent runs.

---

### Step 2: Environment Selection

**If you have existing environments:**
```
Available Environments:
  [env-12345] Production
  [env-67890] Development
  [t36303] Test Environment

Use existing environment? (y/n) [y]:
```

**Choose:**
- `y` - Use existing environment (enter the ID like `t36303`)
- `n` - Create new environment (enter a name)

---

### Step 3: Cluster Selection

**If you selected an existing environment:**
```
Available Clusters:
  [lkc-abc123] prod-cluster - AWS:us-east-1 (MULTI_ZONE)
  [lkc-0o3yd2] pg-test-datagen - AWS:us-east-1 (SINGLE_ZONE)

Use existing cluster? (y/n) [y]:
```

**Choose:**
- `y` - Use existing cluster (enter the ID like `lkc-0o3yd2`)
- `n` - Create new cluster

**If creating new cluster:**
```
Cluster name [kafka-cluster-1714012800]: my-cluster
Cloud Providers:
  1) AWS
  2) GCP
  3) Azure
Select cloud provider [1]: 1
Region [us-east-1]: us-east-1
Cluster Availability:
  1) SINGLE_ZONE (Basic - lower cost)
  2) MULTI_ZONE (High availability)
Select [1]: 1
```

---

### Step 4: Connector Configuration

```
Select Connector Type:
  1) DatagenSource - Generate sample data (PAGEVIEWS, ORDERS, USERS)
  2) DatagenSource - ORDERS
  3) DatagenSource - USERS
  4) DatagenSource - CLICKSTREAM
  5) Custom configuration

Select connector type [1]: 2

Connector name [datagen-1714012800]: orders-generator
Topic name [orders]: orders
```

**Connector Templates:**
- **Option 1:** PAGEVIEWS - Sample web page view events
- **Option 2:** ORDERS - E-commerce order events
- **Option 3:** USERS - User profile data
- **Option 4:** CLICKSTREAM - User clickstream events
- **Option 5:** Custom - Specify your own settings

---

### Step 5: Review and Deploy

```
Deployment Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Environment:  t36303 (existing)
Cluster:      lkc-0o3yd2 (existing)
              pg-test-datagen - AWS:us-east-1
Connector:    orders-generator
Type:         DatagenSource
Topic:        orders
Template:     ORDERS

Proceed with deployment? (y/n) [y]:
```

**Choose:**
- `y` - Deploy now
- `n` - Cancel deployment

---

## Deployment Examples

### Example 1: Add Connector to Existing Cluster (Fastest)

**Scenario:** You have a cluster and want to add a connector

```bash
./deploy-connector.sh

# Answers:
Use saved credentials? y
Use existing environment? y → t36303
Use existing cluster? y → lkc-0o3yd2
Connector type: 2 (ORDERS)
Connector name: orders-datagen
Topic name: orders
Proceed? y

# Time: ~2 minutes
# Creates: Only the connector
```

---

### Example 2: New Cluster + Connector

**Scenario:** Create a new cluster and connector in existing environment

```bash
./deploy-connector.sh

# Answers:
Use saved credentials? y
Use existing environment? y → env-prod
Use existing cluster? n
Cluster name: analytics-cluster
Cloud: 1 (AWS)
Region: us-west-2
Availability: 1 (SINGLE_ZONE)
Connector type: 3 (USERS)
Connector name: user-events
Topic: users
Proceed? y

# Time: ~3-5 minutes
# Creates: Cluster + connector + service accounts + ACLs
```

---

### Example 3: Full Stack (New Environment)

**Scenario:** Starting completely from scratch

```bash
./deploy-connector.sh

# Answers:
Use saved credentials? y
Use existing environment? n
Environment name: Development
Use existing cluster? n
Cluster name: dev-kafka
Cloud: 1 (AWS)
Region: us-east-1
Availability: 1 (SINGLE_ZONE)
Connector type: 1 (PAGEVIEWS)
Connector name: test-datagen
Topic: pageviews
Proceed? y

# Time: ~5-7 minutes
# Creates: Environment + cluster + connector + everything
```

---

## What Gets Deployed

### Connector Only (Existing Environment + Existing Cluster)

```
✓ Connector service account
✓ API key for connector
✓ The connector itself
```

**Time:** ~2 minutes

---

### Cluster + Connector (Existing Environment)

```
✓ Kafka cluster
✓ Admin service account
✓ Admin role binding
✓ Admin API key
✓ Connector service account
✓ Connector API key
✓ 4 ACLs (READ, WRITE, CREATE, consumer group)
✓ The connector
```

**Time:** ~3-5 minutes

---

### Full Stack (New Environment)

```
✓ Environment
✓ Kafka cluster
✓ Admin service account
✓ Admin role binding
✓ Admin API key
✓ Connector service account
✓ Connector API key
✓ 4 ACLs
✓ The connector
```

**Time:** ~5-7 minutes

---

## After Deployment

### View Results

The script shows:
```
✓ Deployment Complete!

Deployment Details:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Environment:  t36303
Cluster:      lkc-0o3yd2

Connectors:
  orders-generator: lcc-xyz789

Status:
  orders-generator: RUNNING

View in Confluent Cloud:
  https://confluent.cloud/environments/t36303
```

---

### Check Connector Status

**In Confluent Cloud UI:**
1. Go to the URL shown in deployment output
2. Navigate to your cluster
3. Click "Connectors" in the sidebar
4. View connector status and logs

**Using Terraform:**
```bash
cd ccloud/terraform-cloud-connector
terraform output connector_status
```

---

### Consume Messages

```bash
# Get connection details
cd ccloud/terraform-cloud-connector
terraform output cluster_bootstrap_endpoint
terraform output -raw api_key_id
terraform output -raw api_key_secret

# Consume from the topic
kafka-console-consumer \
  --bootstrap-server <bootstrap-endpoint> \
  --topic orders \
  --from-beginning \
  --max-messages 10
```

---

## Files Created

### .env
Contains your saved credentials (auto-reused on next run)
```bash
export CONFLUENT_CLOUD_API_KEY="..."
export CONFLUENT_CLOUD_API_SECRET="..."
```

### terraform.tfvars
Contains the deployment configuration
```hcl
confluent_cloud_api_key    = "..."
use_existing_environment   = true
environment_id             = "t36303"
connector_configs = [...]
```

### .deployment_info
Contains deployment metadata
```bash
ENVIRONMENT_ID=t36303
CLUSTER_ID=lkc-0o3yd2
CONNECTOR_NAME=orders-generator
DEPLOYED_AT=Thu Apr 24 12:34:56 UTC 2026
```

---

## Cleanup

### To delete all resources:

```bash
cd ccloud/terraform-cloud-connector
terraform destroy -auto-approve
```

**What gets deleted:**
- Connectors
- Service accounts
- API keys
- ACLs
- Cluster (if created by script)
- Environment (if created by script)

**What stays:**
- Existing environments (not managed by script)
- Existing clusters (not managed by script)

---

## Common Scenarios

### Scenario: Add Multiple Connectors to Same Cluster

**Run the script multiple times:**

```bash
# First connector
./deploy-connector.sh
# Select: existing env → existing cluster → ORDERS connector

# Second connector
./deploy-connector.sh
# Select: existing env → same cluster → USERS connector

# Third connector
./deploy-connector.sh
# Select: existing env → same cluster → CLICKSTREAM connector
```

**Note:** Each run adds a new connector. Existing connectors remain running.

---

### Scenario: Test Different Connector Types

```bash
# Try PAGEVIEWS
./deploy-connector.sh
# Create test cluster → PAGEVIEWS → test

# Clean up
terraform destroy -auto-approve

# Try ORDERS
./deploy-connector.sh
# Create test cluster → ORDERS → test

# Clean up
terraform destroy -auto-approve
```

---

### Scenario: Production Deployment

```bash
./deploy-connector.sh

# Recommended settings:
Environment: existing (env-prod)
Cluster: existing (lkc-prod-01) or new with MULTI_ZONE
Connector: Meaningful name (e.g., "prod-orders-cdc")
Review carefully before proceeding!
```

---

## Troubleshooting

### Issue: "Invalid credentials"

**Cause:** Wrong API key or secret  
**Solution:** 
1. Delete `.env` file: `rm .env`
2. Run script again and enter correct credentials
3. Verify credentials at: https://confluent.cloud

---

### Issue: "Environment not found"

**Cause:** Invalid environment ID  
**Solution:** Check available environments in Confluent Cloud UI or let script list them

---

### Issue: "Cluster not found"

**Cause:** Cluster doesn't exist or not in selected environment  
**Solution:** Verify cluster ID in Confluent Cloud UI

---

### Issue: Deployment stuck

**Cause:** Network issue or API rate limiting  
**Solution:** 
1. Wait a few minutes
2. Press Ctrl+C to cancel
3. Run `terraform destroy` to clean up partial deployment
4. Try again

---

## Tips

### ✅ Reuse Existing Infrastructure

Save costs by using existing environments and clusters when possible.

### ✅ Use Meaningful Names

Name connectors descriptively: `prod-orders-cdc`, `dev-test-datagen`, etc.

### ✅ Review Before Deploy

Always review the deployment summary before proceeding.

### ✅ Save Credentials

Let the script save credentials to `.env` for faster subsequent deployments.

### ✅ Test in Development First

Create test clusters in dev environment before deploying to production.

---

## Summary

**The deploy-connector.sh script provides:**

✅ **Interactive prompts** - No manual configuration  
✅ **Credential management** - Save and reuse  
✅ **Environment reuse** - Avoid hitting limits  
✅ **Cluster reuse** - Reduce costs  
✅ **Guided connector setup** - Pre-built templates  
✅ **Review step** - Confirm before deploy  
✅ **Automatic deployment** - One command  

**Perfect for:**
- Quick testing
- Adding connectors to existing clusters
- Creating new test environments
- Production deployments (with care)

**Get started now:**
```bash
cd ccloud/terraform-cloud-connector
./deploy-connector.sh
```

🚀 Happy deploying!
