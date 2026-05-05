# Terraform Cloud Connector Tool

**🎯 Interactive Deployment - Just answer a few questions!**

```bash
cd ccloud/terraform-cloud-connector
./deploy-connector.sh
```

**OR using playground:**

```bash
playground run -f ccloud/terraform-cloud-connector/deploy-connector.sh
```

**The script will ask you:**
1. 🔑 **Confluent Cloud API credentials** (saved for reuse)
2. 📦 **Environment** - Use existing or create new?
3. 🖥️ **Cluster** - Use existing or create new?
4. 🔌 **Connector type** - DatagenSource (PAGEVIEWS, ORDERS, USERS, CLICKSTREAM)
5. ✅ **Review and deploy** - One command!

**Zero manual configuration required!**

---

**🚀 Or use the Zero-Config Installation - Get running in ONE command!**

A Terraform-based tool for provisioning Confluent Cloud clusters (lkc-*) and fully managed connectors (lcc-*) in the Kafka Docker Playground.

## ⚡ Ultra Quick Start (30 seconds)

```bash
cd ccloud/terraform-cloud-connector
./bootstrap.sh   # That's it! No manual setup needed.
```

The script automatically:
- ✅ Installs all dependencies (Terraform, jq, CLI tools)
- ✅ Configures your credentials (interactive prompts)
- ✅ Deploys your first cluster with Datagen
- ✅ Shows you exactly what was created

**For complete zero-config documentation, see [ZERO_CONFIG_INSTALL.md](ZERO_CONFIG_INSTALL.md)**

---

## 🎯 Overview

This tool allows you to:
- ✅ Provision Confluent Cloud Kafka clusters using Terraform
- ✅ Create fully managed connectors with declarative configuration
- ✅ Manage infrastructure as code with versioning
- ✅ Integrate seamlessly with the Kafka Docker Playground ecosystem
- ✅ Support multiple cloud providers (AWS, GCP, Azure)
- ✅ **NEW: Zero-config automation scripts** - No manual setup!

## 📋 Prerequisites (Auto-Installed!)

1. **Terraform** (>= 1.0)
   ```bash
   # Install on macOS
   brew install terraform
   
   # Install on Linux
   wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
   unzip terraform_1.7.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **Confluent Cloud Account** with API credentials
   - Create API keys at https://confluent.cloud
   - Requires Cloud API Key (not cluster-specific)

3. **Environment Variables**
   ```bash
   export CONFLUENT_CLOUD_API_KEY="your-cloud-api-key"
   export CONFLUENT_CLOUD_API_SECRET="your-cloud-api-secret"
   
   # For AWS connectors
   export AWS_ACCESS_KEY_ID="your-aws-key"
   export AWS_SECRET_ACCESS_KEY="your-aws-secret"
   export AWS_REGION="us-east-1"
   ```

## 🚀 Quick Start

### Using with Playground Run (Recommended)

```bash
# Set credentials
export CONFLUENT_CLOUD_API_KEY="your-cloud-api-key"
export CONFLUENT_CLOUD_API_SECRET="your-cloud-api-secret"

# Run Datagen example
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh

# Or run S3 Sink example (requires AWS credentials)
playground run -f ccloud/terraform-cloud-connector/terraform-s3-sink-example.sh
```

See [PLAYGROUND_RUN.md](PLAYGROUND_RUN.md) for complete playground integration guide.

### Using Standalone Tool

### 1. Basic Cluster Creation

Create a Kafka cluster without connectors:

```bash
cd ccloud/terraform-cloud-connector

# Initialize Terraform
./terraform-cloud-connector.sh --init

# Preview changes
./terraform-cloud-connector.sh --plan

# Create cluster
./terraform-cloud-connector.sh --apply
```

### 2. Create Cluster with Datagen Connector

```bash
./terraform-cloud-connector.sh --apply \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```

### 3. Create AWS S3 Sink Connector

```bash
# Update examples/s3-sink.json with your bucket details
./terraform-cloud-connector.sh --apply \
  --connector-type S3_SINK \
  --connector-config examples/s3-sink.json \
  --cloud AWS \
  --region us-east-1
```

### 4. Destroy Resources

```bash
./terraform-cloud-connector.sh --destroy
```

## 📁 Project Structure

```
terraform-cloud-connector/
├── main.tf                      # Main Terraform configuration
├── variables.tf                 # Variable definitions
├── outputs.tf                   # Output definitions
├── connectors.tf                # Connector resources
├── terraform-cloud-connector.sh # Main script
├── examples/                    # Example connector configs
│   ├── s3-sink.json
│   ├── datagen.json
│   ├── mongodb-sink.json
│   ├── postgresql-source.json
│   └── http-sink.json
└── README.md                    # This file
```

## 🔌 Supported Connectors

**ALL 96+ Confluent Cloud Fully Managed Connectors are Supported!**

See **[examples/CONNECTOR_CATALOG.md](examples/CONNECTOR_CATALOG.md)** for the complete list organized by category:

- 📦 **AWS** (11) - S3, Lambda, Kinesis, DynamoDB, SQS, CloudWatch, Redshift
- 📦 **Azure** (13) - Blob Storage, CosmosDB, Event Hubs, Functions, Synapse
- 📦 **GCP** (7) - GCS, BigQuery, Pub/Sub, Cloud Functions, Bigtable, Spanner
- 📦 **Databases** (16) - PostgreSQL, MySQL, SQL Server, Oracle (JDBC + CDC), Snowflake
- 📦 **NoSQL** (14) - MongoDB, Redis, Elasticsearch, OpenSearch, Couchbase, Neo4j
- 📦 **Messaging** (8) - MQTT, RabbitMQ, IBM MQ, ActiveMQ, Solace
- 📦 **SaaS** (15) - Salesforce, ServiceNow, GitHub, Jira, Zendesk
- 📦 **Analytics** (5) - Snowflake, Databricks, Splunk
- 📦 **Monitoring** (4) - Datadog, InfluxDB
- 📦 **File Transfer** (4) - SFTP
- 📦 **Other** (5) - HTTP, Datagen

**How to use any connector:**
1. Find your connector in [CONNECTOR_CATALOG.md](examples/CONNECTOR_CATALOG.md)
2. Copy the config from `ccloud/fm-<connector>/config-*.json`
3. Customize with your credentials
4. Deploy with Terraform!

See **[examples/README.md](examples/README.md)** for detailed usage guide.

## 🔧 Configuration

### Cluster Configuration

Customize cluster settings in the script:

```bash
./terraform-cloud-connector.sh --apply \
  --cluster-name "my-kafka-cluster" \
  --cloud GCP \
  --region us-central1
```

### Connector Configuration

Create custom connector configs in JSON format. Example for S3 Sink:

```json
{
  "topics": "my_topic",
  "topics.dir": "data",
  "aws.access.key.id": "${AWS_ACCESS_KEY_ID}",
  "aws.secret.access.key": "${AWS_SECRET_ACCESS_KEY}",
  "s3.bucket.name": "my-bucket",
  "s3.region": "us-east-1",
  "input.data.format": "AVRO",
  "output.data.format": "AVRO",
  "time.interval": "HOURLY",
  "flush.size": "1000",
  "tasks.max": "1"
}
```

## 📊 Supported Connectors

The tool supports all Confluent Cloud fully managed connectors:

### Source Connectors
- 🔌 **Datagen** - Generate test data
- 🗄️ **PostgreSQL CDC** - Database change data capture
- 🗄️ **MySQL CDC** - Database change data capture
- 🗄️ **SQL Server CDC** - Database change data capture
- ☁️ **AWS S3** - Stream from S3 buckets
- ☁️ **AWS Kinesis** - Stream from Kinesis
- ☁️ **GCP Pub/Sub** - Stream from Pub/Sub
- 📨 **HTTP** - Pull data from HTTP endpoints
- And 90+ more...

### Sink Connectors
- ☁️ **AWS S3** - Write to S3 buckets
- 🗄️ **MongoDB** - Write to MongoDB
- 🗄️ **PostgreSQL** - Write to PostgreSQL
- 🔍 **Elasticsearch** - Index to Elasticsearch
- 📊 **BigQuery** - Load to BigQuery
- 📨 **HTTP** - Push to HTTP endpoints
- And 100+ more...

## 🎯 Advanced Usage

### Multiple Connectors

Edit `terraform.tfvars` manually to add multiple connectors:

```hcl
connector_configs = [
  {
    name             = "datagen-pageviews"
    connector_class  = "DATAGEN"
    kafka_api_key    = var.confluent_cloud_api_key
    kafka_api_secret = var.confluent_cloud_api_secret
    config = {
      kafka.topic         = "pageviews"
      quickstart          = "PAGEVIEWS"
      output.data.format  = "AVRO"
      tasks.max           = "1"
    }
  },
  {
    name             = "s3-sink-orders"
    connector_class  = "S3_SINK"
    kafka_api_key    = var.confluent_cloud_api_key
    kafka_api_secret = var.confluent_cloud_api_secret
    config = {
      topics              = "orders"
      s3.bucket.name      = "my-bucket"
      input.data.format   = "AVRO"
      output.data.format  = "JSON"
      tasks.max           = "1"
    }
  }
]
```

Then apply:
```bash
terraform apply -auto-approve
```

### Custom Terraform Modules

You can extend the configuration by adding custom Terraform modules:

1. Create a new `.tf` file in the directory
2. Define additional resources (topics, ACLs, schemas, etc.)
3. Run `terraform plan` to preview
4. Apply changes with `terraform apply`

### Integration with Playground

After creating resources, the tool generates a `.ccloud_env` file:

```bash
# Source the environment
source .ccloud_env

# Use with playground commands
playground topic list
playground connector list
```

## 📝 Examples

### Example 1: Data Pipeline with Datagen + S3 Sink

```bash
# Step 1: Create custom config
cat > my-pipeline.json << EOF
{
  "topics": "events",
  "s3.bucket.name": "my-events-bucket",
  "s3.region": "us-east-1",
  "aws.access.key.id": "$AWS_ACCESS_KEY_ID",
  "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
  "input.data.format": "AVRO",
  "output.data.format": "JSON",
  "time.interval": "HOURLY",
  "flush.size": "1000",
  "tasks.max": "1"
}
EOF

# Step 2: Create infrastructure
./terraform-cloud-connector.sh --apply \
  --connector-type S3_SINK \
  --connector-config my-pipeline.json
```

### Example 2: Multi-Region Deployment

```bash
# Deploy to GCP us-central1
./terraform-cloud-connector.sh --apply \
  --cluster-name "gcp-cluster" \
  --cloud GCP \
  --region us-central1
```

### Example 3: Development Environment

```bash
# Create minimal development cluster with Datagen
./terraform-cloud-connector.sh --apply \
  --cluster-name "dev-cluster" \
  --connector-type DATAGEN \
  --connector-config examples/datagen.json
```

## 🔐 Security Best Practices

1. **Never commit sensitive data**
   - `.tfvars` files are gitignored
   - Use environment variables for secrets

2. **Use least-privilege IAM**
   - Connector service accounts have minimal required permissions
   - ACLs are scoped to specific resources

3. **Enable audit logs**
   - Track all Terraform changes
   - Monitor connector activity

4. **Rotate credentials regularly**
   - Update API keys periodically
   - Use short-lived credentials when possible

## 🐛 Troubleshooting

### Terraform Init Fails

```bash
# Clear Terraform cache
rm -rf .terraform .terraform.lock.hcl
./terraform-cloud-connector.sh --init
```

### Connector Creation Fails

1. Check connector configuration format
2. Verify required fields for connector type
3. Review Confluent Cloud quotas and limits
4. Check service account permissions

### API Authentication Errors

```bash
# Verify credentials
echo $CONFLUENT_CLOUD_API_KEY
echo $CONFLUENT_CLOUD_API_SECRET

# Test with Confluent CLI
confluent login --save
confluent environment list
```

## 📚 Resources

- [Confluent Terraform Provider Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)
- [Confluent Cloud Connectors](https://docs.confluent.io/cloud/current/connectors/index.html)
- [Kafka Docker Playground](https://kafka-docker-playground.io)
- [Example Repository](https://github.com/Amitninja12345/terraform-provider-confluent)

## 🤝 Contributing

Contributions welcome! Please:
1. Add new connector examples to `examples/`
2. Update README with new features
3. Test changes before submitting PRs

## 📄 License

Part of the Kafka Docker Playground project.

## 🆘 Support

For issues and questions:
- GitHub Issues: [kafka-docker-playground](https://github.com/vdesabou/kafka-docker-playground/issues)
- Confluent Community: [forum.confluent.io](https://forum.confluent.io)
