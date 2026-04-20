# Running with Playground Command

The Terraform Cloud Connector tool can be run using the standard `playground run` command, just like other examples in the playground.

## 🚀 Quick Start with Playground Run

### Option 1: Using Playground Run (Recommended for Playground Users)

```bash
# Set required environment variables
export CONFLUENT_CLOUD_API_KEY="your-cloud-api-key"
export CONFLUENT_CLOUD_API_SECRET="your-cloud-api-secret"

# Run Datagen example
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh

# Or run S3 Sink example
export AWS_ACCESS_KEY_ID="your-aws-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret"
playground run -f ccloud/terraform-cloud-connector/terraform-s3-sink-example.sh
```

### Option 2: Direct Execution

```bash
# Navigate to directory
cd ccloud/terraform-cloud-connector

# Run directly
./terraform-datagen-example.sh

# Or S3 example
./terraform-s3-sink-example.sh
```

### Option 3: Using the Standalone Tool

```bash
cd ccloud/terraform-cloud-connector

# More control over configuration
./terraform-cloud-connector.sh --apply \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```

### Option 4: Using Make

```bash
cd ccloud/terraform-cloud-connector

# Quick shortcuts
make datagen        # Datagen connector
make s3-sink       # S3 Sink connector
```

## 📋 Available Example Scripts

### 1. terraform-datagen-example.sh
**What it does:**
- Creates Confluent Cloud cluster (lkc-*)
- Deploys Datagen source connector (lcc-*)
- Generates test pageview data
- Verifies data generation

**Run with:**
```bash
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh
```

**Required environment variables:**
- `CONFLUENT_CLOUD_API_KEY`
- `CONFLUENT_CLOUD_API_SECRET`

---

### 2. terraform-s3-sink-example.sh
**What it does:**
- Creates Confluent Cloud cluster (lkc-*)
- Creates S3 bucket
- Deploys Datagen source connector (lcc-*)
- Deploys S3 Sink connector (lcc-*)
- Verifies end-to-end data flow

**Run with:**
```bash
playground run -f ccloud/terraform-cloud-connector/terraform-s3-sink-example.sh
```

**Required environment variables:**
- `CONFLUENT_CLOUD_API_KEY`
- `CONFLUENT_CLOUD_API_SECRET`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (optional, defaults to us-east-1)

---

## 🔧 How It Works

The playground-compatible scripts:

1. **Source playground utilities** - Use `scripts/utils.sh` for logging and helpers
2. **Bootstrap Terraform** - Initialize and configure Terraform
3. **Create infrastructure** - Apply Terraform configuration
4. **Verify resources** - Check cluster and connector status
5. **Cleanup** - Prompt for resource destruction

## 📊 What You Get

After running any example:

```
✅ Infrastructure created successfully!

📊 Cluster Details:
   Environment ID: env-xxxxx
   Cluster ID:     lkc-xxxxx
   Bootstrap:      pkc-xxxxx.aws.confluent.cloud:9092

🔌 Connector Details:
   Connector ID:   lcc-xxxxx
   Type:          DatagenSource
   Topic:         terraform_pageviews

💾 Saving cluster configuration...
```

A `.ccloud_env` file is created with:
- Cluster ID
- API credentials
- Bootstrap servers

## 🎯 Using with Playground Commands

After the script runs, you can use playground commands:

```bash
# Source the environment
source ccloud/terraform-cloud-connector/.ccloud_env

# Use playground commands
playground topic list
playground connector list
playground connector status --connector DatagenSource_user
playground topic consume --topic terraform_pageviews --min-expected-messages 10
```

## 🔄 Typical Workflow

```bash
# 1. Set credentials
export CONFLUENT_CLOUD_API_KEY="your-key"
export CONFLUENT_CLOUD_API_SECRET="your-secret"

# 2. Run example with playground
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh

# 3. Script will:
#    - Create cluster
#    - Deploy connector
#    - Verify data
#    - Prompt for cleanup

# 4. Or keep running and explore
#    (answer 'n' when prompted to delete)

# 5. Source environment
source ccloud/terraform-cloud-connector/.ccloud_env

# 6. Use playground commands
playground connector list

# 7. Clean up later
cd ccloud/terraform-cloud-connector && ./stop.sh
```

## 🆚 Comparison: Different Ways to Run

| Method | Best For | Pros | Cons |
|--------|----------|------|------|
| **playground run** | Playground users | Consistent with other examples | Less customization |
| **Direct script** | Quick testing | Simple, fast | Limited options |
| **terraform-cloud-connector.sh** | Advanced users | Full control, flexible | More complex |
| **Make** | Developers | Easy to remember | Requires Make |

## 📝 Creating Custom Examples

Want to create your own playground-compatible example? Follow this template:

```bash
#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Your connector logic here
# Use log, logerror, logwarn for output
# Use check_if_continue for cleanup prompts

log "🚀 My Custom Terraform Example"

# Check prerequisites
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    logerror "CONFLUENT_CLOUD_API_KEY required"
    exit 1
fi

# Navigate to terraform directory
cd "$DIR"

# Create terraform.tfvars
cat > terraform.tfvars << EOF
confluent_cloud_api_key    = "$CONFLUENT_CLOUD_API_KEY"
confluent_cloud_api_secret = "$CONFLUENT_CLOUD_API_SECRET"
# ... your config
EOF

# Apply terraform
terraform init
terraform apply -auto-approve

# Verify
log "✅ Infrastructure created!"

# Cleanup prompt
log "Delete infrastructure?"
check_if_continue
terraform destroy -auto-approve
```

Save as `terraform-my-connector.sh`, make executable, and run with:
```bash
playground run -f ccloud/terraform-cloud-connector/terraform-my-connector.sh
```

## 🐛 Troubleshooting

### Script not found
```bash
# Make sure you're in the playground root directory
cd /path/to/kafka-docker-playground
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh
```

### Terraform not found
```bash
# Install Terraform first
brew install terraform  # macOS
# or
sudo apt-get install terraform  # Linux
```

### Missing credentials
```bash
# Set all required variables
export CONFLUENT_CLOUD_API_KEY="your-key"
export CONFLUENT_CLOUD_API_SECRET="your-secret"
export AWS_ACCESS_KEY_ID="your-aws-key"        # For AWS examples
export AWS_SECRET_ACCESS_KEY="your-aws-secret"  # For AWS examples
```

## 📚 Additional Resources

- [QUICKSTART.md](QUICKSTART.md) - 5-minute getting started
- [README.md](README.md) - Full documentation
- [OVERVIEW.md](OVERVIEW.md) - Architecture and concepts
- [Kafka Docker Playground Docs](https://kafka-docker-playground.io)

## 🎉 Summary

You can run the Terraform Cloud Connector tool in multiple ways:

1. ✅ **playground run** - Consistent with playground examples
2. ✅ **Direct execution** - Quick and simple
3. ✅ **Standalone tool** - Full control
4. ✅ **Make shortcuts** - Easy commands

All methods create the same infrastructure and work seamlessly with playground commands!
