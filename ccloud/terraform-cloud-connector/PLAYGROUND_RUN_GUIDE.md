# Playground Run Guide - Automated 🎮

## ⚡ Quick Start with Playground Run

### Automated Datagen (Recommended)
```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh
```

**What happens:**
- ✅ Auto-installs Terraform (if needed)
- ✅ Prompts for credentials (saved for next time)
- ✅ Deploys cluster + Datagen connector
- ✅ Verifies everything works
- ✅ Prompts before cleanup

**Time**: 2-3 minutes | **Manual steps**: Enter credentials once

---

### Automated Pipeline (Datagen → S3)
```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-pipeline.sh
```

**What happens:**
- ✅ Same auto-setup as Datagen
- ✅ Prompts for AWS credentials
- ✅ Deploys complete pipeline
- ✅ Verifies data flow
- ✅ Shows S3 bucket location

**Time**: 3-4 minutes | **Manual steps**: Enter AWS credentials

---

### Interactive Wizard
```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh
```

**What happens:**
- ✅ Asks 4-5 simple questions
- ✅ Builds configuration for you
- ✅ Deploys based on your answers
- ✅ No manual file editing!

**Time**: 3-5 minutes | **Manual steps**: Answer questions

---

## 🎯 Available Playground Scripts

| Script | What It Does | Time | Credentials Needed |
|--------|--------------|------|-------------------|
| `playground-auto-datagen.sh` | Datagen only | 2-3 min | Confluent Cloud |
| `playground-auto-pipeline.sh` | Full pipeline | 3-4 min | Confluent + AWS |
| `playground-auto-wizard.sh` | Interactive | 3-5 min | Depends on choice |

---

## 📝 All Scripts Support

### Auto-Installation
- Detects if Terraform is missing
- Installs automatically (macOS/Linux)
- Installs jq and other dependencies

### Credential Management
- Checks environment variables first
- Looks for `.env` file
- Prompts interactively if needed
- Saves for next run

### Playground Integration
- Uses `playground connector status`
- Uses `playground topic consume`
- Saves to `.ccloud_env` for playground commands
- Compatible with all playground workflows

### Error Handling
- Clear error messages
- Validation before deployment
- Automatic retry on transient errors
- Clean rollback on failure

---

## 🔧 Using with Playground Commands

After deployment:

```bash
# Source the environment
source ccloud/terraform-cloud-connector/.ccloud_env

# Use playground commands
playground topic list
playground connector list
playground connector status --connector DatagenSource_$(whoami)
playground topic consume --topic pageviews --max-messages 10
```

---

## 🎮 Complete Workflow Examples

### Example 1: Quick Test
```bash
# Run automated Datagen
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh

# When prompted, choose to keep running
# Then use playground commands:
source ccloud/terraform-cloud-connector/.ccloud_env
playground topic consume --topic pageviews

# Clean up when done (re-run and choose cleanup)
```

### Example 2: S3 Pipeline
```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export S3_BUCKET="my-kafka-bucket"

# Run pipeline
playground run -f ccloud/terraform-cloud-connector/playground-auto-pipeline.sh

# Verify S3 writes
aws s3 ls s3://my-kafka-bucket/topics/pipeline_data/
```

### Example 3: Custom Configuration with Wizard
```bash
# Interactive setup
playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh

# Answer questions:
# 1. Choose pipeline
# 2. Enter topic name
# 3. Choose GCP
# 4. Confirm deployment
```

---

## 🔄 Comparison: Manual vs Automated

### Manual Playground Run (Old Way)
```bash
# Set credentials manually
export CONFLUENT_CLOUD_API_KEY="..."
export CONFLUENT_CLOUD_API_SECRET="..."
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# Run example
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh

# Hope everything is configured correctly!
```

### Automated Playground Run (New Way)
```bash
# Just run it!
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh

# Script handles everything:
# - Checks dependencies
# - Prompts for credentials
# - Saves for next time
# - Auto-configures
# - Deploys
# - Verifies
```

---

## 💡 Pro Tips

### Tip 1: Save Credentials
First run will prompt for credentials and save to `.env`:
```bash
# First time
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh
# Enter credentials → Saved

# Next time
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh
# No prompts → Uses saved credentials
```

### Tip 2: Use Environment Variables
```bash
# Set once
export CONFLUENT_CLOUD_API_KEY="your-key"
export CONFLUENT_CLOUD_API_SECRET="your-secret"

# Run multiple times
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh
playground run -f ccloud/terraform-cloud-connector/playground-auto-pipeline.sh
```

### Tip 3: Multi-Cloud Testing
```bash
# Test AWS
AWS_REGION=us-east-1 playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh

# Test GCP (use wizard)
playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh
# Choose GCP option
```

### Tip 4: Keep Infrastructure Running
When prompted "Delete infrastructure?", choose **No** to keep it running.

Then use playground commands:
```bash
source ccloud/terraform-cloud-connector/.ccloud_env
playground topic consume --topic pageviews
playground connector status --connector DatagenSource_$(whoami)
```

To destroy later:
```bash
cd ccloud/terraform-cloud-connector
terraform destroy -auto-approve
```

---

## 🐛 Troubleshooting

### Issue: "Terraform not found"
**Auto-fixed!** Script installs it automatically.

### Issue: "Missing credentials"
**Auto-prompted!** Script asks for them interactively.

### Issue: "AWS credentials needed"
```bash
# Set before running
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

# Or enter when prompted
playground run -f ccloud/terraform-cloud-connector/playground-auto-pipeline.sh
```

### Issue: Want to change configuration
Use the wizard:
```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh
```

---

## 📊 What Gets Created

```
Confluent Cloud:
├── Environment (pg-auto-env-{user})
├── Kafka Cluster (lkc-xxxxx)
├── Service Account (sa-xxxxx)
├── API Keys (auto-created)
└── Connector(s) (lcc-xxxxx)

Local Files:
├── .env (your credentials, gitignored)
├── .ccloud_env (cluster details for playground)
├── terraform.tfstate (infrastructure state)
└── .terraform/ (terraform cache)
```

---

## 🎉 Success Criteria

After running any automated script, you should see:

```
✅ Terraform installed (or already installed)
✅ Credentials configured
✅ Cluster created (lkc-xxxxx)
✅ Connector deployed (lcc-xxxxx)
✅ Connector is RUNNING
✅ Environment saved to .ccloud_env
```

Then you can use playground commands immediately!

---

## 📚 Related Documentation

- **Quick Testing**: See `HOW_TO_TEST.md`
- **Zero-Config Guide**: See `ZERO_CONFIG_INSTALL.md`
- **Complete Guide**: See `README.md`
- **Original Examples**: `terraform-datagen-example.sh`, `terraform-s3-sink-example.sh`

---

## 🚀 Summary

**Before**: Manual setup, multiple steps, error-prone
**After**: One command, fully automated, self-guiding

```bash
playground run -f ccloud/terraform-cloud-connector/playground-auto-datagen.sh
```

**Zero manual configuration. Complete automation. Playground-native.**
