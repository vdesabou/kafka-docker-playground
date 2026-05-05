# Terraform Cloud Connector Tool - Overview

## 🎯 What This Tool Does

This tool integrates Terraform with the Kafka Docker Playground to provision and manage Confluent Cloud infrastructure:

- **Cloud Clusters (lkc-\*)**: Creates Kafka clusters in AWS, GCP, or Azure
- **Cloud Connectors (lcc-\*)**: Deploys fully managed connectors
- **Infrastructure as Code**: Version control your cloud resources
- **Playground Integration**: Works seamlessly with existing playground tools

## 📁 Project Structure

```
ccloud/terraform-cloud-connector/
│
├── Core Terraform Files
│   ├── main.tf              - Cluster, environment, service accounts
│   ├── variables.tf         - Input variable definitions
│   ├── outputs.tf          - Output definitions (cluster ID, API keys)
│   ├── connectors.tf       - Connector resource definitions
│   └── versions.tf         - Terraform version requirements
│
├── Scripts & Tools
│   ├── terraform-cloud-connector.sh  - Main CLI tool
│   ├── stop.sh                       - Cleanup/destroy resources
│   ├── validate-setup.sh            - Validate prerequisites
│   └── Makefile                     - Common command shortcuts
│
├── Documentation
│   ├── README.md           - Full documentation
│   ├── QUICKSTART.md       - 5-minute getting started guide
│   └── OVERVIEW.md         - This file
│
└── examples/
    ├── Connector Configurations (JSON)
    │   ├── datagen.json            - Test data generator
    │   ├── s3-sink.json           - AWS S3 sink
    │   ├── mongodb-sink.json      - MongoDB sink
    │   ├── postgresql-source.json - PostgreSQL CDC source
    │   └── http-sink.json         - HTTP webhook sink
    │
    ├── Advanced Examples (Terraform)
    │   ├── existing-cluster.tf.example      - Import existing clusters
    │   └── multi-connector.tfvars.example   - Multiple connectors
    │
    └── Complete Examples (Shell)
        └── complete-pipeline.sh    - End-to-end data pipeline
```

## 🚀 Quick Usage Examples

### 1. Create Basic Cluster
```bash
./terraform-cloud-connector.sh --apply
```
**Result**: Creates a basic Kafka cluster without connectors

### 2. Cluster + Datagen Connector
```bash
./terraform-cloud-connector.sh --apply \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```
**Result**: Cluster with test data generation

### 3. Complete S3 Pipeline
```bash
./examples/complete-pipeline.sh
```
**Result**: Cluster + Datagen source + S3 sink

### 4. Destroy Everything
```bash
./stop.sh
# or
make destroy
```

## 🔧 Key Features

### ✅ Multi-Cloud Support
- AWS, GCP, Azure
- Any region supported by Confluent Cloud
- Configurable cluster availability (SINGLE_ZONE, MULTI_ZONE)

### ✅ 100+ Connector Types
- **Sources**: Datagen, PostgreSQL, MySQL, S3, Kinesis, Pub/Sub, etc.
- **Sinks**: S3, BigQuery, Elasticsearch, MongoDB, HTTP, etc.

### ✅ Security Built-In
- Service accounts with least-privilege ACLs
- API key management
- Sensitive data protection (.gitignore configured)

### ✅ Playground Integration
- Generates `.ccloud_env` file for playground CLI
- Compatible with existing playground scripts
- Follows playground conventions

## 📊 Resource Outputs

After applying, the tool outputs:

```bash
Cluster Details:
  Environment ID:    env-xxxxx
  Cluster ID:        lkc-xxxxx (use this for connectors!)
  Bootstrap:         xxx.confluent.cloud:9092
  REST Endpoint:     https://xxx.confluent.cloud:443

Service Account:
  Account ID:        sa-xxxxx
  API Key:          <key>
  API Secret:       <secret>

Connectors:
  Connector Name:    lcc-xxxxx (cloud connector ID!)
  Status:           RUNNING/PROVISIONING/FAILED
```

## 🎓 Learning Path

1. **Start Here**: [QUICKSTART.md](QUICKSTART.md)
   - 5-minute setup
   - First cluster creation
   - Common scenarios

2. **Go Deeper**: [README.md](README.md)
   - All configuration options
   - Advanced use cases
   - Troubleshooting guide

3. **Experiment**: `examples/`
   - Try different connectors
   - Run complete pipeline
   - Customize configurations

4. **Extend**: Terraform files
   - Add custom resources
   - Create your own modules
   - Build reusable templates

## 🔑 Key Concepts

### Cluster ID (lkc-*)
- Unique identifier for your Kafka cluster
- Required for connector creation
- Output after cluster creation
- Example: `lkc-abc123`

### Connector ID (lcc-*)
- Unique identifier for your connector
- Automatically generated when connector is created
- Used for monitoring and management
- Example: `lcc-xyz789`

### Service Account
- Identity for connectors to access Kafka
- Automatically created by this tool
- Has minimal required permissions (ACLs)
- One service account per cluster

### API Keys
- Used for authentication
- Cloud API Key: For Terraform operations
- Cluster API Key: For connector authentication

## 🔄 Typical Workflow

```bash
# 1. Validate setup
./validate-setup.sh

# 2. Preview changes
make plan

# 3. Create infrastructure
make apply

# 4. Verify resources
make outputs

# 5. Use with playground
source .ccloud_env
playground connector list

# 6. Make changes
# Edit terraform.tfvars or connector configs

# 7. Apply updates
terraform apply

# 8. Clean up when done
make destroy
```

## 🆚 This Tool vs. Manual Creation

| Aspect | Manual (UI/CLI) | This Tool (Terraform) |
|--------|----------------|----------------------|
| **Repeatability** | Manual steps each time | Single command |
| **Version Control** | No tracking | Git-based |
| **Multi-Environment** | Error-prone | Consistent |
| **Documentation** | Separate docs | Code is documentation |
| **Rollback** | Manual | `terraform destroy` |
| **Team Collaboration** | Difficult | Easy with Git |

## 🎯 Use Cases

### Development
- Quickly spin up test environments
- Generate test data with Datagen
- Experiment with different connectors
- Learn Confluent Cloud features

### Testing
- Create consistent test infrastructure
- Automate integration tests
- CI/CD pipeline integration
- Load testing environments

### Production
- Infrastructure as Code (IaC)
- Multi-region deployments
- Disaster recovery setups
- Change management and auditing

### Education
- Learn Terraform and Confluent Cloud
- Understand connector configurations
- Practice with safe environments
- Build reference architectures

## 🔐 Security Considerations

1. **Never commit secrets**
   - `.tfvars` files are gitignored
   - Use environment variables

2. **Use separate environments**
   - Dev/Staging/Prod isolation
   - Different API keys per environment

3. **Enable audit logs**
   - Track all Terraform changes
   - Monitor connector activity

4. **Rotate credentials**
   - Regular API key rotation
   - Use short-lived credentials

## 📚 Additional Resources

- [Confluent Terraform Provider](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)
- [Confluent Cloud Docs](https://docs.confluent.io/cloud/current/)
- [Kafka Docker Playground](https://kafka-docker-playground.io)
- [Example Repository](https://github.com/Amitninja12345/terraform-provider-confluent)

## 🤝 Contributing

Want to improve this tool? We welcome:
- New connector examples
- Documentation improvements
- Bug fixes
- Feature requests

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/vdesabou/kafka-docker-playground/issues)
- **Forum**: [Confluent Community](https://forum.confluent.io)
- **Docs**: Check README.md and QUICKSTART.md

---

**Ready to get started?** → [QUICKSTART.md](QUICKSTART.md)
