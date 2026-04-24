# Zero-Config Installation 🚀

**Get a Confluent Cloud cluster running in ONE command - no manual steps!**

## ⚡ Ultra Quick Start (30 seconds)

```bash
cd ccloud/terraform-cloud-connector
./bootstrap.sh
```

That's it! The script will:
- ✅ Install all dependencies (Terraform, jq, Confluent CLI)
- ✅ Configure credentials (prompts you once)
- ✅ Deploy your first cluster with Datagen
- ✅ Show you what was created

## 🎯 What Gets Automated

| Old Way (Manual) | New Way (Automated) |
|-----------------|---------------------|
| Install Terraform manually | ✅ Auto-installed |
| Set environment variables | ✅ Auto-configured |
| Edit JSON config files | ✅ Generated for you |
| Run multiple commands | ✅ One command |
| Remember Terraform syntax | ✅ Interactive wizard |

## 🛠️ Four Ways to Run (Pick Your Style)

### 1️⃣ Bootstrap (Recommended for First-Timers)
**Best for**: First time users, complete automation
```bash
./bootstrap.sh
# Interactive menu guides you through everything
```

### 2️⃣ Interactive Wizard
**Best for**: Users who want guided setup with choices
```bash
./wizard.sh
# Answer a few questions, get exactly what you want
```

### 3️⃣ Quick Launch
**Best for**: Users who know what they want
```bash
./quick-launch.sh datagen          # Test data
./quick-launch.sh pipeline         # Datagen → S3
./quick-launch.sh demo             # Full demo
```

### 4️⃣ Traditional CLI
**Best for**: Power users, automation scripts
```bash
./terraform-cloud-connector.sh --apply \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```

## 📋 Script Overview

```
┌─────────────────┐
│  bootstrap.sh   │  ← Start here! Master menu
└────────┬────────┘
         │
         ├──────────────────┐
         │                  │
    ┌────▼─────┐      ┌────▼──────┐
    │ setup.sh │      │ wizard.sh │
    └──────────┘      └───────────┘
         │                  │
         │            ┌─────▼──────────┐
         │            │ quick-launch.sh│
         │            └────────────────┘
         │                  │
         └──────────┬───────┘
                    │
         ┌──────────▼───────────────────┐
         │ terraform-cloud-connector.sh │
         └──────────────────────────────┘
```

### `bootstrap.sh` - Your Starting Point
- Master menu with all options
- First-time user detection
- Guides you to the right tool

### `setup.sh` - Automated Environment Setup
- Installs Terraform, jq, Confluent CLI
- Detects OS (macOS/Linux) and uses appropriate package manager
- Configures credentials (interactive or from files)
- Validates setup
- Creates example configs

### `wizard.sh` - Interactive Configuration
- Asks questions in plain English
- Builds config files for you
- No manual JSON editing
- Previews before deploying

### `quick-launch.sh` - One-Command Scenarios
- Pre-configured templates
- Common use cases ready to go
- Minimal prompts

## 🎬 Complete Example Flows

### Example 1: Absolute Beginner
```bash
# Clone repo
git clone <repo-url>
cd ccloud/terraform-cloud-connector

# ONE command
./bootstrap.sh

# Choose option 1 (Quick Start)
# Script does everything automatically
# Cluster ready in 2-3 minutes!
```

### Example 2: Developer Testing
```bash
# Quick test environment
./quick-launch.sh datagen

# View what was created
make outputs

# Clean up
make destroy
```

### Example 3: Production Pipeline
```bash
# Interactive setup with custom configs
./wizard.sh

# Choose "Complete Pipeline"
# Answer questions about your S3 bucket
# Script builds and deploys everything
```

## 🔑 Credentials Handling (Automated!)

The setup script handles credentials in smart ways:

1. **Checks environment variables** first
2. **Looks for existing config** files (~/.confluent/config.json)
3. **Prompts interactively** if not found
4. **Saves to .env** for future runs
5. **Validates credentials** before continuing

No need to manually export variables!

## 📊 What Gets Created

After running bootstrap or wizard:

```
Your Project Directory:
├── .env                    ← Your credentials (gitignored)
├── .terraform/             ← Terraform state (auto-created)
├── terraform.tfstate       ← Infrastructure state
├── .ccloud_env             ← Confluent Cloud details
└── examples/
    ├── datagen.json        ← Auto-generated
    └── *.json              ← More examples

In Confluent Cloud:
├── Environment: playground-env-{user}
├── Kafka Cluster: lkc-xxxxx
├── Service Account: sa-xxxxx
├── API Keys: auto-created
└── Connectors: lcc-xxxxx (based on your choice)
```

## 🚫 What You DON'T Need to Do

- ❌ Manually install Terraform
- ❌ Read Terraform documentation
- ❌ Edit JSON config files
- ❌ Set environment variables
- ❌ Remember complex commands
- ❌ Understand Terraform state
- ❌ Configure providers
- ❌ Debug missing dependencies

All automated! 🎉

## 🐛 Troubleshooting (Auto-Fixed!)

Most issues are automatically detected and fixed:

| Issue | Auto-Fix |
|-------|----------|
| Terraform not installed | Installs it for you |
| Missing credentials | Prompts interactively |
| Invalid JSON config | Uses validated templates |
| Wrong region | Suggests alternatives |
| Dependency missing | Installs automatically |

If something fails, the scripts provide clear error messages and suggestions.

## ⚙️ Advanced: Customization

Even with automation, you can customize:

```bash
# Custom cloud/region
./quick-launch.sh datagen --cloud GCP --region us-central1

# Skip prompts
./bootstrap.sh --quick

# Setup only (no deployment)
./setup.sh
```

## 📦 Comparison with Manual Setup

### Manual Approach (Old):
```bash
# 1. Install Terraform
brew install terraform

# 2. Set credentials
export CONFLUENT_CLOUD_API_KEY="..."
export CONFLUENT_CLOUD_API_SECRET="..."

# 3. Create config file
cat > datagen.json << EOF
{
  "connector.class": "DatagenSource",
  ...
}
EOF

# 4. Initialize Terraform
terraform init

# 5. Apply configuration
terraform apply -var connector_type=DATAGEN ...

# Time: ~10-15 minutes
# Steps: 5+
# Errors: Many possible
```

### Automated Approach (New):
```bash
./bootstrap.sh

# Time: ~2 minutes
# Steps: 1
# Errors: Auto-handled
```

## 🎓 Learning Path

1. **Start**: Run `./bootstrap.sh` → Choose Quick Start
2. **Learn**: See what was created with `make outputs`
3. **Experiment**: Try `./wizard.sh` with different options
4. **Customize**: Edit generated configs in `examples/`
5. **Master**: Use direct CLI for automation

## 🔗 Integration with Playground

These automation scripts integrate seamlessly with the Kafka Docker Playground:

```bash
# Playground-compatible
playground run -f ccloud/terraform-cloud-connector/bootstrap.sh

# Environment auto-loaded
source .ccloud_env
playground connector status
```

## 💡 Pro Tips

1. **First run**: Use `bootstrap.sh` for complete hand-holding
2. **Repeat users**: Use `quick-launch.sh` for speed
3. **Custom needs**: Use `wizard.sh` for flexibility
4. **CI/CD**: Use direct CLI with `--auto-approve`
5. **Learning**: Run with verbose mode to see what happens

## 🎉 Success Criteria

After running bootstrap, you should see:

```
✔ Terraform installed
✔ Dependencies configured
✔ Credentials validated
✔ Cluster created (lkc-xxxxx)
✔ Connector deployed (lcc-xxxxx)
✔ Connector status: RUNNING
```

**You're ready to stream! 🚀**

## 📞 Need Help?

```bash
# Built-in help
./bootstrap.sh --help
./wizard.sh --help
./quick-launch.sh --help

# Validate setup
./validate-setup.sh

# Check status
make status

# View full documentation
cat README.md
```

---

**No manual steps. No confusion. Just working Kafka clusters.** ⚡
