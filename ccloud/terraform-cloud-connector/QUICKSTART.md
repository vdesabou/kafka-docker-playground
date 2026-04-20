# Quick Start Guide

Get started with the Terraform Cloud Connector Tool in 5 minutes!

## 🚀 1-Minute Setup

### Prerequisites
```bash
# Install Terraform
brew install terraform  # macOS
# or
sudo apt-get install terraform  # Linux

# Set credentials
export CONFLUENT_CLOUD_API_KEY="your-api-key"
export CONFLUENT_CLOUD_API_SECRET="your-api-secret"
```

### Create Your First Cluster
```bash
cd ccloud/terraform-cloud-connector

# Option 1: Using Make
make datagen

# Option 2: Using the script
./terraform-cloud-connector.sh --apply \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```

That's it! You now have a running Confluent Cloud cluster with a Datagen connector.

## 📚 Common Scenarios

### Scenario 1: Generate Test Data
**Use Case**: I need a cluster with test data for development

```bash
# Create cluster with Datagen (generates pageviews)
make datagen

# View cluster details
make outputs

# Check connector status
make status
```

### Scenario 2: Stream to S3
**Use Case**: I want to archive Kafka data to S3

```bash
# 1. Set AWS credentials
export AWS_ACCESS_KEY_ID="your-aws-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret"
export AWS_REGION="us-east-1"

# 2. Update S3 bucket in examples/s3-sink.json
vim examples/s3-sink.json

# 3. Create infrastructure
./terraform-cloud-connector.sh --apply \
  --connector-type S3_SINK \
  --connector-config examples/s3-sink.json
```

### Scenario 3: Complete Data Pipeline
**Use Case**: Generate data AND write to S3

```bash
# Run the complete pipeline example
./examples/complete-pipeline.sh
```

This creates:
- ✅ Confluent Cloud cluster
- ✅ Datagen source (generates data)
- ✅ S3 sink (stores data)
- ✅ Verifies end-to-end data flow

### Scenario 4: Multi-Cloud Deployment
**Use Case**: Deploy to GCP instead of AWS

```bash
./terraform-cloud-connector.sh --apply \
  --cluster-name "gcp-cluster" \
  --cloud GCP \
  --region us-central1 \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```

### Scenario 5: Multiple Connectors
**Use Case**: I need multiple connectors on one cluster

```bash
# 1. Copy example config
cp examples/multi-connector.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars with your settings
vim terraform.tfvars

# 3. Apply
terraform apply -auto-approve
```

## 🎯 Understanding the Files

```
terraform-cloud-connector/
│
├── *.tf                    # Terraform configuration
│   ├── main.tf             # Cluster & environment
│   ├── connectors.tf       # Connector resources
│   ├── variables.tf        # Input variables
│   └── outputs.tf          # Output values
│
├── terraform-cloud-connector.sh  # Main CLI tool
├── stop.sh                       # Cleanup script
├── Makefile                      # Shortcuts
│
└── examples/
    ├── *.json              # Connector configs
    └── complete-pipeline.sh # Full example
```

## 🔧 Essential Commands

```bash
# Check environment
make check-env

# Preview changes
make plan

# Create infrastructure
make apply

# View outputs
make outputs

# Clean up
make destroy

# Format code
make format
```

## 📊 Working with Resources

### View Cluster ID
```bash
terraform output cluster_id
# Output: lkc-xxxxx
```

### View API Keys
```bash
terraform output -json | jq -r '.api_key_id.value'
terraform output -json | jq -r '.api_key_secret.value'
```

### View Connector IDs
```bash
terraform output -json | jq -r '.connector_ids.value'
# Output: { "connector-name": "lcc-xxxxx" }
```

### Use with Playground CLI
```bash
# Load environment
source .ccloud_env

# Use playground commands
playground topic list
playground connector list
playground connector status --connector DATAGEN_user
```

## 🐛 Troubleshooting

### Problem: "Error: Failed to query available provider packages"
**Solution**: Run `terraform init` first
```bash
make init
```

### Problem: "Error: Invalid credentials"
**Solution**: Check your API keys
```bash
echo $CONFLUENT_CLOUD_API_KEY
echo $CONFLUENT_CLOUD_API_SECRET

# Make sure they're Cloud API keys, not cluster-specific keys
```

### Problem: "Error: Connector creation failed"
**Solution**: Check connector configuration format
```bash
# Validate JSON format
cat examples/datagen.json | jq '.'

# Check required fields for your connector type
```

### Problem: Resources not cleaned up
**Solution**: Force destroy
```bash
terraform destroy -auto-approve
rm -rf .terraform terraform.tfstate*
```

## 💡 Pro Tips

### Tip 1: Save Costs
Use `SINGLE_ZONE` clusters for development:
```bash
# Already default in variables.tf
cluster_availability = "SINGLE_ZONE"
```

### Tip 2: Faster Iterations
Use Makefile shortcuts:
```bash
make plan   # Instead of terraform-cloud-connector.sh --plan
make apply  # Instead of terraform-cloud-connector.sh --apply
```

### Tip 3: Multiple Environments
Use workspaces:
```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
```

### Tip 4: Version Control
Commit only these files:
```bash
git add *.tf Makefile README.md examples/*.json
# Never commit: terraform.tfvars, .tfstate, .ccloud_env
```

### Tip 5: Reuse Existing Clusters
See `examples/existing-cluster.tf.example` for importing existing clusters.

## 🎓 Next Steps

1. ✅ **Completed Quick Start** - You have a working cluster!

2. 📖 **Read Full Documentation** - Check `README.md` for advanced features

3. 🔌 **Try Different Connectors** - Explore 100+ connector types:
   - Source: PostgreSQL, MySQL, MongoDB, Kinesis, etc.
   - Sink: S3, BigQuery, Elasticsearch, HTTP, etc.

4. 🏗️ **Customize Infrastructure** - Edit `*.tf` files for:
   - Topics with schemas
   - ACLs and permissions
   - Multiple environments
   - Advanced networking

5. 🤝 **Contribute** - Add new examples or improve docs!

## 📞 Getting Help

- 📚 [Full README](README.md)
- 🐛 [Report Issues](https://github.com/vdesabou/kafka-docker-playground/issues)
- 💬 [Confluent Forum](https://forum.confluent.io)
- 📖 [Terraform Provider Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)

---

**Happy Terraforming! 🚀**
