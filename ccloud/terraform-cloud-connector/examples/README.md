# Connector Examples

This directory contains example configurations for all 96+ Confluent Cloud fully managed connectors.

## 📚 Quick Reference

- **[CONNECTOR_CATALOG.md](CONNECTOR_CATALOG.md)** - Complete reference with all 96+ connectors
- **Category Directories** - Organized examples by connector type
- **Playground Configs** - Source configs from `ccloud/fm-*` directories

## 🗂️ Organization

```
examples/
├── CONNECTOR_CATALOG.md      # Complete connector reference (ALL 96+)
├── README.md                  # This file
│
├── aws/                       # AWS connectors (11)
│   ├── s3-sink.json
│   ├── s3-source.json
│   ├── lambda-sink.json
│   ├── kinesis-source.json
│   ├── dynamodb-sink.json
│   └── ...
│
├── azure/                     # Azure connectors (13)
│   ├── blob-storage-sink.json
│   ├── cosmosdb-sink.json
│   ├── event-hubs-source.json
│   └── ...
│
├── gcp/                       # GCP connectors (7)
│   ├── gcs-sink.json
│   ├── bigquery-sink.json
│   ├── pubsub-source.json
│   └── ...
│
├── databases/                 # Database connectors (16)
│   ├── postgresql-source.json
│   ├── mysql-source.json
│   ├── debezium-postgresql-cdc.json
│   └── ...
│
├── nosql/                     # NoSQL connectors (14)
│   ├── mongodb-sink.json
│   ├── elasticsearch-sink.json
│   ├── redis-sink.json
│   └── ...
│
├── messaging/                 # Messaging connectors (8)
│   ├── mqtt-source.json
│   ├── rabbitmq-source.json
│   └── ...
│
├── saas/                      # SaaS connectors (15)
│   ├── salesforce-cdc-source.json
│   ├── servicenow-source.json
│   └── ...
│
├── analytics/                 # Analytics & Data Warehouse (5)
│   ├── snowflake-sink.json
│   ├── databricks-delta-lake-sink.json
│   └── ...
│
├── monitoring/                # Monitoring & Observability (4)
│   ├── datadog-metrics-sink.json
│   └── ...
│
├── file-transfer/             # File Transfer (4)
│   ├── sftp-sink.json
│   └── ...
│
├── datagen.json              # Test data generator
├── http-sink.json            # HTTP webhook sink
└── http-source.json          # HTTP source
```

## 🚀 How to Use

### Method 1: Use Pre-Made Examples

```bash
# Browse available examples
ls examples/aws/
ls examples/databases/

# Use an example
./terraform-cloud-connector.sh --apply \
  --connector-type S3_SINK \
  --connector-config examples/aws/s3-sink.json
```

### Method 2: Create from Playground Configs

All playground connector configs are available in `ccloud/fm-*/config-*.json`:

```bash
# Find a connector config
find ../../ccloud/fm-* -name "config-*.json" | grep mongodb

# Copy and customize
cp ../../ccloud/fm-mongodb-atlas-sink/config-MongoDbAtlasSink.json \
   examples/my-mongodb-config.json

# Edit with your values
vim examples/my-mongodb-config.json

# Use it
./terraform-cloud-connector.sh --apply \
  --connector-type MongoDbAtlasSink \
  --connector-config examples/my-mongodb-config.json
```

### Method 3: Use Terraform Variables

For complex setups with multiple connectors, use `terraform.tfvars`:

```hcl
# terraform.tfvars
connector_configs = [
  {
    name             = "datagen-source"
    connector_class  = "DatagenSource"
    kafka_api_key    = var.confluent_cloud_api_key
    kafka_api_secret = var.confluent_cloud_api_secret
    config = {
      "kafka.topic"        = "pageviews"
      "quickstart"         = "PAGEVIEWS"
      "output.data.format" = "AVRO"
      "tasks.max"          = "1"
    }
  },
  {
    name             = "s3-sink"
    connector_class  = "S3_SINK"
    kafka_api_key    = var.confluent_cloud_api_key
    kafka_api_secret = var.confluent_cloud_api_secret
    config = {
      "topics"              = "pageviews"
      "s3.bucket.name"      = "my-bucket"
      "aws.access.key.id"   = var.aws_access_key_id
      "aws.secret.access.key" = var.aws_secret_access_key
      "input.data.format"   = "AVRO"
      "output.data.format"  = "JSON"
      "tasks.max"           = "1"
    }
  }
]
```

Then apply:
```bash
terraform apply -auto-approve
```

## 📋 Common Configuration Patterns

### AWS Connectors

**Authentication Options**:
1. Access Keys: `aws.access.key.id` + `aws.secret.access.key`
2. Provider Integration: `provider.integration.id` (recommended)

**Required Fields** (S3 Sink example):
```json
{
  "topics": "my-topic",
  "s3.bucket.name": "my-bucket",
  "s3.region": "us-east-1",
  "aws.access.key.id": "${AWS_ACCESS_KEY_ID}",
  "aws.secret.access.key": "${AWS_SECRET_ACCESS_KEY}",
  "input.data.format": "AVRO",
  "output.data.format": "JSON",
  "tasks.max": "1"
}
```

### Azure Connectors

**Authentication Options**:
1. Storage Account Key: `azblob.account.key`
2. SAS Token: `azblob.sas.token`
3. Service Principal: `azblob.client.id` + `azblob.client.secret`

### GCP Connectors

**Authentication Options**:
1. Service Account JSON: `gcp.credentials.json`
2. Provider Integration: `provider.integration.id` (recommended)

### Database Connectors (JDBC)

**Required Fields**:
```json
{
  "connection.host": "hostname",
  "connection.port": "5432",
  "connection.user": "username",
  "connection.password": "password",
  "db.name": "database",
  "table.whitelist": "schema.table",
  "mode": "incrementing",
  "incrementing.column.name": "id",
  "output.data.format": "AVRO",
  "tasks.max": "1"
}
```

### CDC Connectors (Debezium)

**Required Fields**:
```json
{
  "database.hostname": "hostname",
  "database.port": "5432",
  "database.user": "username",
  "database.password": "password",
  "database.dbname": "database",
  "database.server.name": "my-server",
  "table.include.list": "public.customers,public.orders",
  "snapshot.mode": "initial",
  "output.data.format": "AVRO",
  "after.state.only": "true",
  "tasks.max": "1"
}
```

### MongoDB Connectors

**Required Fields**:
```json
{
  "connection.url": "mongodb+srv://user:pass@cluster.mongodb.net",
  "database": "mydb",
  "collection": "mycollection",
  "output.data.format": "JSON",
  "copy.existing": "true",
  "tasks.max": "1"
}
```

### Salesforce Connectors

**Required Fields**:
```json
{
  "salesforce.username": "user@company.com",
  "salesforce.password": "password",
  "salesforce.password.token": "security-token",
  "salesforce.object": "Account",
  "salesforce.instance": "https://company.my.salesforce.com",
  "kafka.topic": "salesforce-accounts",
  "output.data.format": "AVRO",
  "tasks.max": "1"
}
```

## 🔍 Finding the Right Connector

### By Use Case

**Streaming to Cloud Storage**:
- AWS → `S3_SINK`
- Azure → `AzureBlobSink`, `AzureDataLakeGen2Sink`
- GCP → `GcsSink`

**Database CDC (Change Data Capture)**:
- PostgreSQL → `DebeziumPostgresSourceV2`
- MySQL → `DebeziumMySqlSourceV2`
- SQL Server → `DebeziumSqlServerSourceV2`
- Oracle → `OracleCdcSource`, `OracleXStreamSource`

**Data Warehousing**:
- Snowflake → `SnowflakeSink`
- BigQuery → `BigQuerySinkV2`
- Databricks → `DatabricksDeltaLakeSink`
- Redshift → `RedshiftSink`

**Search & Analytics**:
- Elasticsearch → `ElasticsearchSink`, `ElasticsearchSinkV2`
- OpenSearch → `OpensearchSink`
- Splunk → `SplunkSink`

**NoSQL Databases**:
- MongoDB → `MongoDbAtlasSink/Source`
- Redis → `RedisSink`
- Cassandra → `CassandraSink`
- Couchbase → `CouchbaseSink/Source`

**Messaging Systems**:
- MQTT → `MqttSource/Sink`
- RabbitMQ → `RabbitMQSource/Sink`
- IBM MQ → `IbmMQSource/Sink`
- ActiveMQ → `ActiveMQSource`

**SaaS Applications**:
- Salesforce → Multiple (CDC, Bulk API, Platform Events, etc.)
- ServiceNow → `ServiceNowSource/Sink`
- Jira → `JiraSource`
- GitHub → `GithubSource`
- Zendesk → `ZendeskSource`

## 📖 Connector Documentation

For detailed documentation on each connector:

1. **[CONNECTOR_CATALOG.md](CONNECTOR_CATALOG.md)** - Quick reference for all connectors
2. **Confluent Docs** - https://docs.confluent.io/cloud/current/connectors/
3. **Playground Configs** - Check `ccloud/fm-<connector>/config-*.json` for full field list

## 🛠️ Customization Tips

### Environment Variables

Use environment variables for sensitive data:

```json
{
  "aws.access.key.id": "${AWS_ACCESS_KEY_ID}",
  "aws.secret.access.key": "${AWS_SECRET_ACCESS_KEY}",
  "database.password": "${DB_PASSWORD}"
}
```

### Provider Integrations (Recommended)

For production, use provider integrations instead of hardcoded credentials:

```json
{
  "provider.integration.id": "cspi-xxxxx"
}
```

No need for access keys when using provider integrations!

### Data Formats

**Common Options**:
- `AVRO` - Schema evolution, compact
- `JSON` - Human-readable, flexible
- `PROTOBUF` - Efficient, typed
- `PARQUET` - Columnar, for analytics

### Tasks Configuration

```json
{
  "tasks.max": "1"  // Start with 1, increase for throughput
}
```

## 🔄 Workflow

1. **Find your connector** in [CONNECTOR_CATALOG.md](CONNECTOR_CATALOG.md)
2. **Check required fields** for that connector
3. **Copy example** or create from playground config
4. **Customize** with your credentials and settings
5. **Test** with a single task (`tasks.max: 1`)
6. **Scale** by increasing tasks if needed

## 🐛 Troubleshooting

### Connector won't start

1. Check required fields are provided
2. Verify credentials are correct
3. Ensure topic/database/bucket exists
4. Check network connectivity
5. Review connector logs in Confluent Cloud UI

### Configuration validation fails

- Use the full config from `ccloud/fm-*/config-*.json` as reference
- Check field names are exact (case-sensitive)
- Verify data formats are supported
- Ensure authentication method is complete

### Can't find a connector

- Check [CONNECTOR_CATALOG.md](CONNECTOR_CATALOG.md) for full list
- Search playground: `find ../../ccloud/fm-* -name "config-*.json"`
- Visit https://docs.confluent.io/cloud/current/connectors/

## 📞 Getting Help

- **Connector Catalog**: [CONNECTOR_CATALOG.md](CONNECTOR_CATALOG.md)
- **Terraform Tool**: `../terraform-cloud-connector.sh --help`
- **Playground**: https://kafka-docker-playground.io
- **Confluent Docs**: https://docs.confluent.io/cloud/current/connectors/
- **GitHub Issues**: https://github.com/vdesabou/kafka-docker-playground/issues

---

**Total Connectors Available**: 96+  
**Categories**: AWS (11), Azure (13), GCP (7), Databases (16), NoSQL (14), Messaging (8), SaaS (15), Analytics (5), Monitoring (4), File Transfer (4), Other (5)
