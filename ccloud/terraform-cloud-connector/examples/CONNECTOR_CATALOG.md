# Fully Managed Connector Catalog

Complete reference for all 96+ Confluent Cloud fully managed connectors.

## 📋 Table of Contents

- [AWS Connectors (11)](#aws-connectors)
- [Azure Connectors (13)](#azure-connectors)
- [GCP Connectors (7)](#gcp-connectors)
- [Database Connectors (16)](#database-connectors)
- [NoSQL Connectors (14)](#nosql-connectors)
- [Messaging Connectors (8)](#messaging-connectors)
- [SaaS Connectors (15)](#saas-connectors)
- [Analytics & Data Warehouse (5)](#analytics--data-warehouse)
- [Monitoring & Observability (4)](#monitoring--observability)
- [File Transfer (4)](#file-transfer)
- [Other Connectors (5)](#other-connectors)

---

## AWS Connectors

### S3 Sink
**Connector Class**: `S3_SINK`  
**Type**: Sink  
**Config File**: `aws/s3-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `s3.bucket.name`: S3 bucket name
- `s3.region`: AWS region
- `aws.access.key.id`: AWS access key OR `provider.integration.id`
- `aws.secret.access.key`: AWS secret key (if using keys)
- `input.data.format`: AVRO, JSON, PROTOBUF
- `output.data.format`: AVRO, JSON, PARQUET
- `tasks.max`: Number of tasks

**Example**:
```bash
./terraform-cloud-connector.sh --apply \
  --connector-type S3_SINK \
  --connector-config examples/aws/s3-sink.json
```

### S3 Source
**Connector Class**: `S3Source`  
**Type**: Source  
**Config File**: `aws/s3-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `s3.bucket.name`: S3 bucket name
- `s3.region`: AWS region
- `aws.access.key.id`: AWS access key OR `provider.integration.id`
- `output.data.format`: AVRO, JSON, PROTOBUF

### Lambda Sink
**Connector Class**: `LambdaSink`  
**Type**: Sink  
**Config File**: `aws/lambda-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `aws.lambda.function.name`: Lambda function name
- `aws.lambda.invocation.type`: REQUEST_RESPONSE or EVENT
- `aws.access.key.id`: AWS credentials

### Kinesis Source
**Connector Class**: `KinesisSource`  
**Type**: Source  
**Config File**: `aws/kinesis-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `kinesis.stream`: Kinesis stream name
- `kinesis.region`: AWS region
- `aws.access.key.id`: AWS credentials

### DynamoDB Sink
**Connector Class**: `DynamoDbSink`  
**Type**: Sink  
**Config File**: `aws/dynamodb-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `aws.dynamodb.region`: AWS region
- `aws.dynamodb.table.name`: DynamoDB table
- `aws.access.key.id`: AWS credentials

### DynamoDB CDC Source
**Connector Class**: `DynamoDbCdcSource`  
**Type**: Source  
**Config File**: `aws/dynamodb-cdc-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `table.name`: DynamoDB table
- `aws.region`: AWS region

### SQS Source
**Connector Class**: `SqsSource`  
**Type**: Source  
**Config File**: `aws/sqs-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `sqs.queue.url`: SQS queue URL
- `aws.access.key.id`: AWS credentials

### CloudWatch Logs Source
**Connector Class**: `CloudWatchLogsSource`  
**Type**: Source  
**Config File**: `aws/cloudwatch-logs-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `log.group`: CloudWatch log group
- `aws.region`: AWS region

### CloudWatch Metrics Sink
**Connector Class**: `CloudWatchMetricsSink`  
**Type**: Sink  
**Config File**: `aws/cloudwatch-metrics-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `aws.cloudwatch.metrics.namespace`: Metrics namespace
- `aws.cloudwatch.metrics.region`: AWS region

### Redshift Sink
**Connector Class**: `RedshiftSink`  
**Type**: Sink  
**Config File**: `aws/redshift-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `aws.redshift.cluster.id`: Redshift cluster ID
- `aws.redshift.database`: Database name
- `aws.redshift.user`: Database user

---

## Azure Connectors

### Blob Storage Sink
**Connector Class**: `AzureBlobSink`  
**Type**: Sink  
**Config File**: `azure/blob-storage-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `azblob.account.name`: Storage account name
- `azblob.account.key`: Storage account key OR `azblob.sas.token`
- `azblob.container.name`: Container name
- `input.data.format`: Data format

### Blob Storage Source
**Connector Class**: `AzureBlobSource`  
**Type**: Source  
**Config File**: `azure/blob-storage-source.json`

### CosmosDB Sink
**Connector Class**: `CosmosDbSink`  
**Type**: Sink  
**Config File**: `azure/cosmosdb-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `azure.cosmos.account.endpoint`: Cosmos endpoint
- `azure.cosmos.master.key`: Master key
- `azure.cosmos.database.name`: Database name
- `azure.cosmos.containers.topicmap`: Topic to container mapping

### CosmosDB Source
**Connector Class**: `CosmosDbSource`  
**Type**: Source  
**Config File**: `azure/cosmosdb-source.json`

### CosmosDB V2 Sink/Source
**Connector Class**: `CosmosDbSinkV2` / `CosmosDbSourceV2`  
**Config Files**: `azure/cosmosdb-v2-*.json`

### Event Hubs Source
**Connector Class**: `AzureEventHubsSource`  
**Type**: Source  
**Config File**: `azure/event-hubs-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `azure.eventhubs.namespace`: Event Hubs namespace
- `azure.eventhubs.hub.name`: Event Hub name
- `azure.eventhubs.sas.key.name`: SAS key name
- `azure.eventhubs.sas.key`: SAS key

### Functions Sink
**Connector Class**: `AzureFunctionsSink`  
**Type**: Sink  
**Config File**: `azure/functions-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `azure.function.url`: Function URL
- `azure.function.key`: Function key

### Data Lake Gen2 Sink
**Connector Class**: `AzureDataLakeGen2Sink`  
**Type**: Sink  
**Config File**: `azure/data-lake-gen2-sink.json`

### Service Bus Source
**Connector Class**: `AzureServiceBusSource`  
**Type**: Source

### Synapse Analytics Sink
**Connector Class**: `AzureSynapseAnalyticsSink`  
**Type**: Sink

### Cognitive Search Sink
**Connector Class**: `AzureCognitiveSearchSink`  
**Type**: Sink

### Log Analytics Sink
**Connector Class**: `AzureLogAnalyticsSink`  
**Type**: Sink

---

## GCP Connectors

### GCS (Cloud Storage) Sink
**Connector Class**: `GcsSink`  
**Type**: Sink  
**Config File**: `gcp/gcs-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `gcs.bucket.name`: GCS bucket name
- `gcp.credentials.json`: Service account JSON OR `provider.integration.id`
- `input.data.format`: Data format
- `output.data.format`: Data format

### GCS Source
**Connector Class**: `GcsSource`  
**Type**: Source  
**Config File**: `gcp/gcs-source.json`

### BigQuery Sink V2
**Connector Class**: `BigQuerySinkV2`  
**Type**: Sink  
**Config File**: `gcp/bigquery-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `project`: GCP project ID
- `datasets`: Dataset name
- `gcp.credentials.json`: Service account JSON
- `auto.create.tables`: true/false
- `auto.update.schemas`: true/false

### Pub/Sub Source
**Connector Class**: `PubSubSource`  
**Type**: Source  
**Config File**: `gcp/pubsub-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `gcp.pubsub.project.id`: GCP project
- `gcp.pubsub.subscription.id`: Subscription ID
- `gcp.credentials.json`: Service account JSON

### Cloud Functions Gen2 Sink
**Connector Class**: `GoogleCloudFunctionsGen2Sink`  
**Type**: Sink  
**Config File**: `gcp/cloud-functions-sink.json`

### Bigtable Sink
**Connector Class**: `BigTableSink`  
**Type**: Sink  
**Config File**: `gcp/bigtable-sink.json`

### Spanner Sink
**Connector Class**: `SpannerSink`  
**Type**: Sink  
**Config File**: `gcp/spanner-sink.json`

---

## Database Connectors

### PostgreSQL Source (JDBC)
**Connector Class**: `PostgresSource`  
**Type**: Source  
**Config File**: `databases/postgresql-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `connection.host`: Database host
- `connection.port`: Database port (default: 5432)
- `connection.user`: Database user
- `connection.password`: Database password
- `db.name`: Database name
- `table.whitelist`: Tables to include
- `mode`: bulk, timestamp, incrementing
- `output.data.format`: Data format

### PostgreSQL Sink (JDBC)
**Connector Class**: `PostgresSink`  
**Type**: Sink  
**Config File**: `databases/postgresql-sink.json`

### PostgreSQL CDC (Debezium)
**Connector Class**: `DebeziumPostgresSourceV2`  
**Type**: Source  
**Config File**: `databases/debezium-postgresql-cdc.json`

**Required Fields**:
- `database.hostname`: PostgreSQL host
- `database.port`: Port (5432)
- `database.user`: Database user
- `database.password`: Password
- `database.dbname`: Database name
- `database.server.name`: Logical server name
- `table.include.list`: Tables to capture (schema.table format)
- `output.data.format`: AVRO recommended
- `snapshot.mode`: initial, never, always
- `after.state.only`: true/false

### MySQL Source (JDBC)
**Connector Class**: `MySqlSource`  
**Type**: Source  
**Config File**: `databases/mysql-source.json`

### MySQL Sink (JDBC)
**Connector Class**: `MySqlSink`  
**Type**: Sink  
**Config File**: `databases/mysql-sink.json`

### MySQL CDC (Debezium)
**Connector Class**: `DebeziumMySqlSourceV2`  
**Type**: Source  
**Config File**: `databases/debezium-mysql-cdc.json`

**Required Fields**:
- `database.hostname`: MySQL host
- `database.port`: Port (3306)
- `database.user`: Database user
- `database.password`: Password
- `database.server.name`: Logical server name
- `table.include.list`: Tables to capture
- `output.data.format`: AVRO
- `snapshot.mode`: initial, when_needed, never

### SQL Server Source (JDBC)
**Connector Class**: `SqlServerSource`  
**Type**: Source  
**Config File**: `databases/sqlserver-source.json`

### SQL Server Sink (JDBC)
**Connector Class**: `SqlServerSink`  
**Type**: Sink

### SQL Server CDC (Debezium)
**Connector Class**: `DebeziumSqlServerSourceV2`  
**Type**: Source

### Oracle Source (JDBC)
**Connector Class**: `OracleSource`  
**Type**: Source  
**Config File**: `databases/oracle-source.json`

### Oracle Sink (JDBC)
**Connector Class**: `OracleSink`  
**Type**: Sink

### Oracle CDC
**Connector Class**: `OracleCdcSource`  
**Type**: Source

### Oracle XStream CDC
**Connector Class**: `OracleXStreamSource`  
**Type**: Source

### MariaDB CDC (Debezium)
**Connector Class**: `DebeziumMariaDbSource`  
**Type**: Source

---

## NoSQL Connectors

### MongoDB Atlas Source
**Connector Class**: `MongoDbAtlasSource`  
**Type**: Source  
**Config File**: `nosql/mongodb-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic (or `topic.prefix`)
- `connection.url`: MongoDB connection string
  - Format: `mongodb+srv://username:password@cluster.mongodb.net`
- `database`: Database name
- `collection`: Collection name
- `output.data.format`: JSON or AVRO
- `copy.existing`: true/false (initial snapshot)

### MongoDB Atlas Sink
**Connector Class**: `MongoDbAtlasSink`  
**Type**: Sink  
**Config File**: `nosql/mongodb-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `connection.url`: MongoDB connection string
- `database`: Database name
- `collection`: Collection name (or use `topics` for auto-mapping)
- `input.data.format`: JSON or AVRO

### MongoDB Source (Community)
**Connector Class**: `MongoDbSource`  
**Type**: Source

### MongoDB Sink (Community)
**Connector Class**: `MongoDbSink`  
**Type**: Sink

### Redis Sink
**Connector Class**: `RedisSink`  
**Type**: Sink  
**Config File**: `nosql/redis-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `redis.host`: Redis host
- `redis.port`: Redis port (default: 6379)
- `redis.password`: Password (if required)
- `redis.command`: SET, RPUSH, LPUSH, etc.

### Redis Source
**Connector Class**: `RedisSource`  
**Type**: Source

### Redis Kafka Sink
**Connector Class**: `RedisKafkaSink`  
**Type**: Sink

### Redis Kafka Source
**Connector Class**: `RedisKafkaSource`  
**Type**: Source

### Elasticsearch Sink
**Connector Class**: `ElasticsearchSink`  
**Type**: Sink  
**Config File**: `nosql/elasticsearch-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `connection.url`: Elasticsearch URL
- `connection.username`: Username
- `connection.password`: Password
- `input.data.format`: Data format
- `behavior.on.null.values`: delete, ignore, fail

### Elasticsearch V2 Sink
**Connector Class**: `ElasticsearchSinkV2`  
**Type**: Sink

### OpenSearch Sink
**Connector Class**: `OpensearchSink`  
**Type**: Sink  
**Config File**: `nosql/opensearch-sink.json`

### Couchbase Source
**Connector Class**: `CouchbaseSource`  
**Type**: Source  
**Config File**: `nosql/couchbase-source.json`

### Couchbase Sink
**Connector Class**: `CouchbaseSink`  
**Type**: Sink

### ClickHouse Sink
**Connector Class**: `ClickHouseSink`  
**Type**: Sink

### Neo4j Sink
**Connector Class**: `Neo4jSink`  
**Type**: Sink

---

## Messaging Connectors

### MQTT Source
**Connector Class**: `MqttSource`  
**Type**: Source  
**Config File**: `messaging/mqtt-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `mqtt.server.uri`: MQTT broker URI
- `mqtt.topics`: MQTT topics to subscribe
- `mqtt.username`: Username (if required)
- `mqtt.password`: Password

### MQTT Sink
**Connector Class**: `MqttSink`  
**Type**: Sink

### RabbitMQ Source
**Connector Class**: `RabbitMQSource`  
**Type**: Source  
**Config File**: `messaging/rabbitmq-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `rabbitmq.host`: RabbitMQ host
- `rabbitmq.port`: Port (default: 5672)
- `rabbitmq.username`: Username
- `rabbitmq.password`: Password
- `rabbitmq.queue`: Queue name

### RabbitMQ Sink
**Connector Class**: `RabbitMQSink`  
**Type**: Sink

### IBM MQ Source
**Connector Class**: `IbmMQSource`  
**Type**: Source  
**Config File**: `messaging/ibm-mq-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `jms.destination.name`: Queue/topic name
- `jms.destination.type`: queue or topic
- `mq.hostname`: MQ hostname
- `mq.port`: Port
- `mq.queue.manager`: Queue manager
- `mq.channel`: Channel

### IBM MQ Sink
**Connector Class**: `IbmMQSink`  
**Type**: Sink

### ActiveMQ Source
**Connector Class**: `ActiveMQSource`  
**Type**: Source  
**Config File**: `messaging/activemq-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `jms.destination.name`: Queue/topic name
- `jms.destination.type`: queue or topic
- `activemq.url`: ActiveMQ broker URL

### Solace Sink
**Connector Class**: `SolaceSink`  
**Type**: Sink

---

## SaaS Connectors

### Salesforce CDC Source
**Connector Class**: `SalesforceCdcSource`  
**Type**: Source  
**Config File**: `saas/salesforce-cdc-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic (or `topic.prefix`)
- `salesforce.username`: Salesforce username
- `salesforce.password`: Password
- `salesforce.password.token`: Security token
- `salesforce.object`: Object name (e.g., Account, Contact)
- `salesforce.instance`: Instance URL
- `output.data.format`: AVRO or JSON

### Salesforce Platform Events Source
**Connector Class**: `SalesforcePlatformEventsSource`  
**Type**: Source

### Salesforce Platform Events Sink
**Connector Class**: `SalesforcePlatformEventsSink`  
**Type**: Sink

### Salesforce PushTopics Source
**Connector Class**: `SalesforcePushTopicsSource`  
**Type**: Source

### Salesforce Bulk API 2.0 Source
**Connector Class**: `SalesforceBulkApi20Source`  
**Type**: Source

### Salesforce Bulk API 2.0 Sink
**Connector Class**: `SalesforceBulkApi20Sink`  
**Type**: Sink

### Salesforce Bulk API Source
**Connector Class**: `SalesforceBulkApiSource`  
**Type**: Source

### Salesforce SObject Sink
**Connector Class**: `SalesforceSObjectSink`  
**Type**: Sink

### ServiceNow Source
**Connector Class**: `ServiceNowSource`  
**Type**: Source  
**Config File**: `saas/servicenow-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `servicenow.url`: ServiceNow instance URL
- `servicenow.user`: Username
- `servicenow.password`: Password
- `servicenow.table`: Table name
- `output.data.format`: Data format

### ServiceNow Sink
**Connector Class**: `ServiceNowSink`  
**Type**: Sink

### ServiceNow V2 Source
**Connector Class**: `ServiceNowSourceV2`  
**Type**: Source

### GitHub Source
**Connector Class**: `GithubSource`  
**Type**: Source  
**Config File**: `saas/github-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `github.service.url`: GitHub URL
- `github.repositories`: Repository list
- `github.access.token`: Personal access token

### Jira Source
**Connector Class**: `JiraSource`  
**Type**: Source  
**Config File**: `saas/jira-source.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `jira.url`: Jira URL
- `jira.username`: Username
- `jira.api.token`: API token
- `jira.jql`: JQL query

### Zendesk Source
**Connector Class**: `ZendeskSource`  
**Type**: Source  
**Config File**: `saas/zendesk-source.json`

---

## Analytics & Data Warehouse

### Snowflake Sink
**Connector Class**: `SnowflakeSink`  
**Type**: Sink  
**Config File**: `databases/snowflake-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `snowflake.url.name`: Snowflake account URL
- `snowflake.user.name`: Username
- `snowflake.private.key`: Private key
- `snowflake.database.name`: Database
- `snowflake.schema.name`: Schema
- `snowflake.topic2table.map`: Topic to table mapping
- `input.data.format`: Data format

### Snowflake Source
**Connector Class**: `SnowflakeSource`  
**Type**: Source

### Databricks Delta Lake Sink
**Connector Class**: `DatabricksDeltaLakeSink`  
**Type**: Sink

**Required Fields**:
- `topics`: Topics to consume
- `delta.lake.host.name`: Databricks host
- `delta.lake.http.path`: HTTP path
- `delta.lake.token`: Access token
- `delta.lake.table.name`: Table name

### Splunk Sink
**Connector Class**: `SplunkSink`  
**Type**: Sink

---

## Monitoring & Observability

### Datadog Metrics Sink
**Connector Class**: `DatadogMetricsSink`  
**Type**: Sink

**Required Fields**:
- `topics`: Topics to consume
- `datadog.api.key`: Datadog API key
- `datadog.domain`: Datadog domain

### InfluxDB 2.x Sink
**Connector Class**: `Influxdb2Sink`  
**Type**: Sink

### InfluxDB 2.x Source
**Connector Class**: `Influxdb2Source`  
**Type**: Source

### InfluxDB 3.x Sink
**Connector Class**: `Influxdb3Sink`  
**Type**: Sink

---

## File Transfer

### SFTP Sink
**Connector Class**: `SftpSink`  
**Type**: Sink

**Required Fields**:
- `topics`: Topics to consume
- `sftp.host`: SFTP host
- `sftp.port`: Port (default: 22)
- `sftp.username`: Username
- `sftp.password`: Password OR `sftp.private.key`

### SFTP Source
**Connector Class**: `SftpSource`  
**Type**: Source

---

## Other Connectors

### HTTP Sink
**Connector Class**: `HttpSink`  
**Type**: Sink  
**Config File**: `http-sink.json`

**Required Fields**:
- `topics`: Topics to consume
- `http.api.url`: HTTP endpoint URL
- `request.method`: GET, POST, PUT, DELETE
- `input.data.format`: Data format
- `auth.type`: NONE, BASIC, OAUTH2

### HTTP Source
**Connector Class**: `HttpSource`  
**Type**: Source  
**Config File**: `http-source.json`

### HTTP V2 Sink
**Connector Class**: `HttpSinkV2`  
**Type**: Sink

### HTTP V2 Source
**Connector Class**: `HttpSourceV2`  
**Type**: Source

### Datagen Source
**Connector Class**: `DatagenSource`  
**Type**: Source  
**Config File**: `datagen.json`

**Required Fields**:
- `kafka.topic`: Destination topic
- `quickstart`: PAGEVIEWS, USERS, ORDERS, etc.
- `output.data.format`: AVRO, JSON
- `max.interval`: Milliseconds between messages
- `iterations`: Total messages to generate
- `tasks.max`: Number of tasks

---

## 🚀 Usage Examples

### Using with Terraform Tool

```bash
cd ccloud/terraform-cloud-connector

# Single connector
./terraform-cloud-connector.sh --apply \
  --connector-type S3_SINK \
  --connector-config examples/aws/s3-sink.json

# Multiple connectors via terraform.tfvars
cp examples/multi-connector.tfvars.example terraform.tfvars
vim terraform.tfvars
terraform apply
```

### Using with Playground

```bash
# Run example
playground run -f ccloud/terraform-cloud-connector/terraform-datagen-example.sh

# View connectors
playground connector list
```

---

## 📚 Additional Resources

- **Confluent Docs**: https://docs.confluent.io/cloud/current/connectors/
- **Terraform Provider**: https://registry.terraform.io/providers/confluentinc/confluent/latest/docs
- **Playground**: https://kafka-docker-playground.io

---

**Last Updated**: 2026-04-20  
**Total Connectors**: 96+  
**Source**: https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud
