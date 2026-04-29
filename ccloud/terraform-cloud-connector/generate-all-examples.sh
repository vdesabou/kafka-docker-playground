#!/bin/bash
set -e

#############################################
# Generate All Connector Examples
#
# Processes all 96+ fully managed connectors
# from kafka-docker-playground and creates
# Terraform-compatible JSON examples
#############################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PLAYGROUND_ROOT="${DIR}/../.."
EXAMPLES_DIR="${DIR}/examples"

echo "🚀 Generating connector examples for all 96+ fully managed connectors..."
echo ""

# Create category directories
mkdir -p "${EXAMPLES_DIR}"/{aws,azure,gcp,databases,nosql,messaging,saas,analytics,monitoring,file-transfer}

# Counter
TOTAL=0
SUCCESS=0
FAILED=0

# Function to create minimal example from playground config
create_example() {
    local connector_name="$1"
    local connector_class="$2"
    local source_config="$3"
    local output_file="$4"
    local connector_type="$5" # source or sink

    if [ ! -f "$source_config" ]; then
        echo "⚠️  Config not found: $source_config"
        ((FAILED++))
        return 1
    fi

    # Create a minimal example with placeholders
    cat > "$output_file" << EOF
{
  "_comment": "Terraform example for $connector_class",
  "_connector_type": "$connector_type",
  "_source": "Generated from kafka-docker-playground",
  "_customize": "Replace placeholder values with your actual configuration"
}
EOF

    # Append the actual config (will be merged in usage)
    jq '.' "$source_config" >> "${output_file}.full" 2>/dev/null || echo "{}" > "${output_file}.full"

    echo "✅ $connector_name → $output_file"
    ((SUCCESS++))
    ((TOTAL++))
}

echo "📦 Generating AWS Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "S3 Sink" "S3_SINK" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-s3-sink/config-S3_SINK.json" \
    "${EXAMPLES_DIR}/aws/s3-sink.json" "sink"

create_example "S3 Source" "S3Source" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-s3-source/config-S3Source.json" \
    "${EXAMPLES_DIR}/aws/s3-source.json" "source"

create_example "Lambda Sink" "LambdaSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-lambda-sink/config-LambdaSink.json" \
    "${EXAMPLES_DIR}/aws/lambda-sink.json" "sink"

create_example "Kinesis Source" "KinesisSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-kinesis-source/config-KinesisSource.json" \
    "${EXAMPLES_DIR}/aws/kinesis-source.json" "source"

create_example "DynamoDB Sink" "DynamoDbSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-dynamodb-sink/config-DynamoDbSink.json" \
    "${EXAMPLES_DIR}/aws/dynamodb-sink.json" "sink"

create_example "DynamoDB CDC Source" "DynamoDbCdcSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-dynamodb-cdc-source/config-DynamoDbCdcSource.json" \
    "${EXAMPLES_DIR}/aws/dynamodb-cdc-source.json" "source"

create_example "SQS Source" "SqsSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-sqs-source/config-SqsSource.json" \
    "${EXAMPLES_DIR}/aws/sqs-source.json" "source"

create_example "CloudWatch Logs Source" "CloudWatchLogsSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-cloudwatch-logs-source/config-CloudWatchLogsSource.json" \
    "${EXAMPLES_DIR}/aws/cloudwatch-logs-source.json" "source"

create_example "CloudWatch Metrics Sink" "CloudWatchMetricsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-cloudwatch-metrics-sink/config-CloudWatchMetricsSink.json" \
    "${EXAMPLES_DIR}/aws/cloudwatch-metrics-sink.json" "sink"

create_example "Redshift Sink" "RedshiftSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-aws-redshift-sink/config-RedshiftSink.json" \
    "${EXAMPLES_DIR}/aws/redshift-sink.json" "sink"

echo ""
echo "📦 Generating Azure Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "Blob Storage Sink" "AzureBlobSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-blob-storage-sink/config-AzureBlobSink.json" \
    "${EXAMPLES_DIR}/azure/blob-storage-sink.json" "sink"

create_example "Blob Storage Source" "AzureBlobSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-blob-storage-source/config-AzureBlobSource.json" \
    "${EXAMPLES_DIR}/azure/blob-storage-source.json" "source"

create_example "CosmosDB Sink" "CosmosDbSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-cosmosdb-sink/config-CosmosDbSink.json" \
    "${EXAMPLES_DIR}/azure/cosmosdb-sink.json" "sink"

create_example "CosmosDB Source" "CosmosDbSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-cosmosdb-source/config-CosmosDbSource.json" \
    "${EXAMPLES_DIR}/azure/cosmosdb-source.json" "source"

create_example "CosmosDB V2 Sink" "CosmosDbSinkV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-cosmosdb-v2-sink/config-CosmosDbSinkV2.json" \
    "${EXAMPLES_DIR}/azure/cosmosdb-v2-sink.json" "sink"

create_example "CosmosDB V2 Source" "CosmosDbSourceV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-cosmosdb-v2-source/config-CosmosDbSourceV2.json" \
    "${EXAMPLES_DIR}/azure/cosmosdb-v2-source.json" "source"

create_example "Event Hubs Source" "AzureEventHubsSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-event-hubs-source/config-AzureEventHubsSource.json" \
    "${EXAMPLES_DIR}/azure/event-hubs-source.json" "source"

create_example "Functions Sink" "AzureFunctionsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-functions-sink/config-AzureFunctionsSink.json" \
    "${EXAMPLES_DIR}/azure/functions-sink.json" "sink"

create_example "Data Lake Gen2 Sink" "AzureDataLakeGen2Sink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-data-lake-storage-gen2-sink/config-AzureDataLakeGen2Sink.json" \
    "${EXAMPLES_DIR}/azure/data-lake-gen2-sink.json" "sink"

create_example "Service Bus Source" "AzureServiceBusSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-service-bus-source/config-AzureServiceBusSource.json" \
    "${EXAMPLES_DIR}/azure/service-bus-source.json" "source"

create_example "Synapse Analytics Sink" "AzureSynapseAnalyticsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-synapse-analytics-sink/config-AzureSynapseAnalyticsSink.json" \
    "${EXAMPLES_DIR}/azure/synapse-analytics-sink.json" "sink"

create_example "Cognitive Search Sink" "AzureCognitiveSearchSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-cognitive-search-sink/config-AzureCognitiveSearchSink.json" \
    "${EXAMPLES_DIR}/azure/cognitive-search-sink.json" "sink"

create_example "Log Analytics Sink" "AzureLogAnalyticsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-azure-log-analytics-sink/config-AzureLogAnalyticsSink.json" \
    "${EXAMPLES_DIR}/azure/log-analytics-sink.json" "sink"

echo ""
echo "📦 Generating GCP Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "GCS Sink" "GcsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-gcs-sink/config-GcsSink.json" \
    "${EXAMPLES_DIR}/gcp/gcs-sink.json" "sink"

create_example "GCS Source" "GcsSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-gcs-source/config-GcsSource.json" \
    "${EXAMPLES_DIR}/gcp/gcs-source.json" "source"

create_example "BigQuery Sink V2" "BigQuerySinkV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-bigquery-v2-sink/config-BigQuerySinkV2.json" \
    "${EXAMPLES_DIR}/gcp/bigquery-sink.json" "sink"

create_example "Pub/Sub Source" "PubSubSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-pubsub-source/config-PubSubSource.json" \
    "${EXAMPLES_DIR}/gcp/pubsub-source.json" "source"

create_example "Cloud Functions Gen2 Sink" "GoogleCloudFunctionsGen2Sink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-cloud-functions-gen2-sink/config-GoogleCloudFunctionsGen2Sink.json" \
    "${EXAMPLES_DIR}/gcp/cloud-functions-sink.json" "sink"

create_example "Bigtable Sink" "BigTableSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-bigtable-sink/config-BigTableSink.json" \
    "${EXAMPLES_DIR}/gcp/bigtable-sink.json" "sink"

create_example "Spanner Sink" "SpannerSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-gcp-spanner-sink/config-SpannerSink.json" \
    "${EXAMPLES_DIR}/gcp/spanner-sink.json" "sink"

echo ""
echo "📦 Generating Database Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# PostgreSQL
create_example "PostgreSQL Source (JDBC)" "PostgresSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-postgresql-source/config-PostgresSource.json" \
    "${EXAMPLES_DIR}/databases/postgresql-source.json" "source"

create_example "PostgreSQL Sink (JDBC)" "PostgresSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-postgresql-sink/config-PostgresSink.json" \
    "${EXAMPLES_DIR}/databases/postgresql-sink.json" "sink"

create_example "PostgreSQL CDC (Debezium)" "DebeziumPostgresSourceV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-debezium-postgresql-v2-source/config-DebeziumPostgresSourceV2.json" \
    "${EXAMPLES_DIR}/databases/debezium-postgresql-cdc.json" "source"

# MySQL
create_example "MySQL Source (JDBC)" "MySqlSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-mysql-source/config-MySqlSource.json" \
    "${EXAMPLES_DIR}/databases/mysql-source.json" "source"

create_example "MySQL Sink (JDBC)" "MySqlSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-mysql-sink/config-MySqlSink.json" \
    "${EXAMPLES_DIR}/databases/mysql-sink.json" "sink"

create_example "MySQL CDC (Debezium)" "DebeziumMySqlSourceV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-debezium-mysql-v2-source/config-DebeziumMySqlSourceV2.json" \
    "${EXAMPLES_DIR}/databases/debezium-mysql-cdc.json" "source"

# SQL Server
create_example "SQL Server Source (JDBC)" "SqlServerSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-sqlserver-source/config-SqlServerSource.json" \
    "${EXAMPLES_DIR}/databases/sqlserver-source.json" "source"

create_example "SQL Server Sink (JDBC)" "SqlServerSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-sqlserver-sink/config-SqlServerSink.json" \
    "${EXAMPLES_DIR}/databases/sqlserver-sink.json" "sink"

create_example "SQL Server CDC (Debezium)" "DebeziumSqlServerSourceV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-debezium-sqlserver-v2-source/config-DebeziumSqlServerSourceV2.json" \
    "${EXAMPLES_DIR}/databases/debezium-sqlserver-cdc.json" "source"

# Oracle
create_example "Oracle Source (JDBC)" "OracleSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-oracle19-source/config-OracleSource.json" \
    "${EXAMPLES_DIR}/databases/oracle-source.json" "source"

create_example "Oracle Sink (JDBC)" "OracleSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-oracle19-sink/config-OracleSink.json" \
    "${EXAMPLES_DIR}/databases/oracle-sink.json" "sink"

create_example "Oracle CDC" "OracleCdcSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-cdc-oracle19-source/config-OracleCdcSource.json" \
    "${EXAMPLES_DIR}/databases/oracle-cdc-source.json" "source"

create_example "Oracle 11 CDC" "OracleCdcSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-cdc-oracle11-source/config-OracleCdcSource.json" \
    "${EXAMPLES_DIR}/databases/oracle11-cdc-source.json" "source"

create_example "Oracle XStream CDC" "OracleXStreamSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-cdc-xstream-oracle19-source/config-OracleXStreamSource.json" \
    "${EXAMPLES_DIR}/databases/oracle-xstream-cdc-source.json" "source"

# MariaDB
create_example "MariaDB CDC (Debezium)" "DebeziumMariaDbSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-debezium-mariadb-source/config-DebeziumMariaDbSource.json" \
    "${EXAMPLES_DIR}/databases/debezium-mariadb-cdc.json" "source"

echo ""
echo "📦 Generating Analytics & Data Warehouse Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "Snowflake Sink" "SnowflakeSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-snowflake-sink/config-SnowflakeSink.json" \
    "${EXAMPLES_DIR}/analytics/snowflake-sink.json" "sink"

create_example "Snowflake Source" "SnowflakeSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-snowflake-source/config-SnowflakeSource.json" \
    "${EXAMPLES_DIR}/analytics/snowflake-source.json" "source"

create_example "Databricks Delta Lake Sink" "DatabricksDeltaLakeSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-databricks-delta-lake-sink/config-DatabricksDeltaLakeSink.json" \
    "${EXAMPLES_DIR}/analytics/databricks-delta-lake-sink.json" "sink"

create_example "Splunk Sink" "SplunkSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-splunk-sink/config-SplunkSink.json" \
    "${EXAMPLES_DIR}/analytics/splunk-sink.json" "sink"

echo ""
echo "📦 Generating NoSQL Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# MongoDB
create_example "MongoDB Atlas Source" "MongoDbAtlasSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-mongodb-atlas-source/config-MongoDbAtlasSource.json" \
    "${EXAMPLES_DIR}/nosql/mongodb-atlas-source.json" "source"

create_example "MongoDB Atlas Sink" "MongoDbAtlasSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-mongodb-atlas-sink/config-MongoDbAtlasSink.json" \
    "${EXAMPLES_DIR}/nosql/mongodb-atlas-sink.json" "sink"

create_example "MongoDB Source" "MongoDbSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-mongodb-source/config-MongoDbSource.json" \
    "${EXAMPLES_DIR}/nosql/mongodb-source.json" "source"

create_example "MongoDB Sink" "MongoDbSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-mongodb-sink/config-MongoDbSink.json" \
    "${EXAMPLES_DIR}/nosql/mongodb-sink.json" "sink"

# Redis
create_example "Redis Sink" "RedisSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-redis-sink/config-RedisSink.json" \
    "${EXAMPLES_DIR}/nosql/redis-sink.json" "sink"

create_example "Redis Kafka Sink" "RedisKafkaSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-redis-kafka-sink/config-RedisKafkaSink.json" \
    "${EXAMPLES_DIR}/nosql/redis-kafka-sink.json" "sink"

create_example "Redis Kafka Source" "RedisKafkaSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-redis-kafka-source/config-RedisKafkaSource.json" \
    "${EXAMPLES_DIR}/nosql/redis-kafka-source.json" "source"

# Search
create_example "Elasticsearch Sink" "ElasticsearchSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-elasticsearch-sink/config-ElasticsearchSink.json" \
    "${EXAMPLES_DIR}/nosql/elasticsearch-sink.json" "sink"

create_example "Elasticsearch V2 Sink" "ElasticsearchSinkV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-elasticsearch-v2-sink/config-ElasticsearchSinkV2.json" \
    "${EXAMPLES_DIR}/nosql/elasticsearch-v2-sink.json" "sink"

create_example "OpenSearch Sink" "OpensearchSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-opensearch-sink/config-OpensearchSink.json" \
    "${EXAMPLES_DIR}/nosql/opensearch-sink.json" "sink"

# Others
create_example "Couchbase Source" "CouchbaseSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-couchbase-source/config-CouchbaseSource.json" \
    "${EXAMPLES_DIR}/nosql/couchbase-source.json" "source"

create_example "Couchbase Sink" "CouchbaseSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-couchbase-sink/config-CouchbaseSink.json" \
    "${EXAMPLES_DIR}/nosql/couchbase-sink.json" "sink"

create_example "ClickHouse Sink" "ClickHouseSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-clickhouse-sink/config-ClickHouseSink.json" \
    "${EXAMPLES_DIR}/nosql/clickhouse-sink.json" "sink"

create_example "Neo4j Sink" "Neo4jSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-neo4j-sink/config-Neo4jSink.json" \
    "${EXAMPLES_DIR}/nosql/neo4j-sink.json" "sink"

echo ""
echo "📦 Generating Messaging Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "MQTT Source" "MqttSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-mqtt-source/config-MqttSource.json" \
    "${EXAMPLES_DIR}/messaging/mqtt-source.json" "source"

create_example "MQTT Sink" "MqttSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-mqtt-sink/config-MqttSink.json" \
    "${EXAMPLES_DIR}/messaging/mqtt-sink.json" "sink"

create_example "RabbitMQ Source" "RabbitMQSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-rabbitmq-source/config-RabbitMQSource.json" \
    "${EXAMPLES_DIR}/messaging/rabbitmq-source.json" "source"

create_example "RabbitMQ Sink" "RabbitMQSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-rabbitmq-sink/config-RabbitMQSink.json" \
    "${EXAMPLES_DIR}/messaging/rabbitmq-sink.json" "sink"

create_example "IBM MQ Source" "IbmMQSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-ibm-mq-source/config-IbmMQSource.json" \
    "${EXAMPLES_DIR}/messaging/ibm-mq-source.json" "source"

create_example "IBM MQ Sink" "IbmMQSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-ibm-mq-sink/config-IbmMQSink.json" \
    "${EXAMPLES_DIR}/messaging/ibm-mq-sink.json" "sink"

create_example "ActiveMQ Source" "ActiveMQSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-active-mq-source/config-ActiveMQSource.json" \
    "${EXAMPLES_DIR}/messaging/activemq-source.json" "source"

create_example "Solace Sink" "SolaceSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-solace-sink/config-SolaceSink.json" \
    "${EXAMPLES_DIR}/messaging/solace-sink.json" "sink"

echo ""
echo "📦 Generating SaaS Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Salesforce
create_example "Salesforce CDC Source" "SalesforceCdcSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-cdc-source/config-SalesforceCdcSource.json" \
    "${EXAMPLES_DIR}/saas/salesforce-cdc-source.json" "source"

create_example "Salesforce Platform Events Source" "SalesforcePlatformEventsSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-platform-events-source/config-SalesforcePlatformEventsSource.json" \
    "${EXAMPLES_DIR}/saas/salesforce-platform-events-source.json" "source"

create_example "Salesforce Platform Events Sink" "SalesforcePlatformEventsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-platform-events-sink/config-SalesforcePlatformEventsSink.json" \
    "${EXAMPLES_DIR}/saas/salesforce-platform-events-sink.json" "sink"

create_example "Salesforce PushTopics Source" "SalesforcePushTopicsSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-pushtopics-source/config-SalesforcePushTopicsSource.json" \
    "${EXAMPLES_DIR}/saas/salesforce-pushtopics-source.json" "source"

create_example "Salesforce Bulk API 2.0 Source" "SalesforceBulkApi20Source" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-bulkapi-2-0-source/config-SalesforceBulkApi20Source.json" \
    "${EXAMPLES_DIR}/saas/salesforce-bulkapi-2-0-source.json" "source"

create_example "Salesforce Bulk API 2.0 Sink" "SalesforceBulkApi20Sink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-bulkapi-2-0-sink/config-SalesforceBulkApi20Sink.json" \
    "${EXAMPLES_DIR}/saas/salesforce-bulkapi-2-0-sink.json" "sink"

create_example "Salesforce Bulk API Source" "SalesforceBulkApiSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-bulkapi-source/config-SalesforceBulkApiSource.json" \
    "${EXAMPLES_DIR}/saas/salesforce-bulkapi-source.json" "source"

create_example "Salesforce SObject Sink" "SalesforceSObjectSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-sobject-sink/config-SalesforceSObjectSink.json" \
    "${EXAMPLES_DIR}/saas/salesforce-sobject-sink.json" "sink"

# ServiceNow
create_example "ServiceNow Source" "ServiceNowSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-servicenow-source/config-ServiceNowSource.json" \
    "${EXAMPLES_DIR}/saas/servicenow-source.json" "source"

create_example "ServiceNow Sink" "ServiceNowSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-servicenow-sink/config-ServiceNowSink.json" \
    "${EXAMPLES_DIR}/saas/servicenow-sink.json" "sink"

create_example "ServiceNow V2 Source" "ServiceNowSourceV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-servicenow-v2-source/config-ServiceNowSourceV2.json" \
    "${EXAMPLES_DIR}/saas/servicenow-v2-source.json" "source"

# Others
create_example "GitHub Source" "GithubSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-github-source/config-GithubSource.json" \
    "${EXAMPLES_DIR}/saas/github-source.json" "source"

create_example "Jira Source" "JiraSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-jira-source/config-JiraSource.json" \
    "${EXAMPLES_DIR}/saas/jira-source.json" "source"

create_example "Zendesk Source" "ZendeskSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-zendesk-source/config-ZendeskSource.json" \
    "${EXAMPLES_DIR}/saas/zendesk-source.json" "source"

echo ""
echo "📦 Generating Monitoring Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "Datadog Metrics Sink" "DatadogMetricsSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-datadog-metrics-sink/config-DatadogMetricsSink.json" \
    "${EXAMPLES_DIR}/monitoring/datadog-metrics-sink.json" "sink"

create_example "InfluxDB 2 Sink" "Influxdb2Sink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-influxdb2-sink/config-Influxdb2Sink.json" \
    "${EXAMPLES_DIR}/monitoring/influxdb2-sink.json" "sink"

create_example "InfluxDB 2 Source" "Influxdb2Source" \
    "${PLAYGROUND_ROOT}/ccloud/fm-influxdb2-source/config-Influxdb2Source.json" \
    "${EXAMPLES_DIR}/monitoring/influxdb2-source.json" "source"

create_example "InfluxDB 3 Sink" "Influxdb3Sink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-influxdb3-sink/config-Influxdb3Sink.json" \
    "${EXAMPLES_DIR}/monitoring/influxdb3-sink.json" "sink"

echo ""
echo "📦 Generating File Transfer Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "SFTP Sink" "SftpSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-sftp-sink/config-SftpSink.json" \
    "${EXAMPLES_DIR}/file-transfer/sftp-sink.json" "sink"

create_example "SFTP Source" "SftpSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-sftp-source/config-SftpSource.json" \
    "${EXAMPLES_DIR}/file-transfer/sftp-source.json" "source"

echo ""
echo "📦 Generating HTTP Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "HTTP Sink" "HttpSink" \
    "${PLAYGROUND_ROOT}/ccloud/fm-http-sink/config-HttpSink.json" \
    "${EXAMPLES_DIR}/http-sink.json" "sink"

create_example "HTTP Source" "HttpSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-http-source/config-HttpSource.json" \
    "${EXAMPLES_DIR}/http-source.json" "source"

create_example "HTTP V2 Sink" "HttpSinkV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-http-v2-sink/config-HttpSinkV2.json" \
    "${EXAMPLES_DIR}/http-v2-sink.json" "sink"

create_example "HTTP V2 Source" "HttpSourceV2" \
    "${PLAYGROUND_ROOT}/ccloud/fm-http-v2-source/config-HttpSourceV2.json" \
    "${EXAMPLES_DIR}/http-v2-source.json" "source"

echo ""
echo "📦 Generating Utility Connector Examples..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_example "Datagen Source" "DatagenSource" \
    "${PLAYGROUND_ROOT}/ccloud/fm-datagen-source/config-DatagenSource.json" \
    "${EXAMPLES_DIR}/datagen.json" "source"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Generation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Statistics:"
echo "   Total Connectors: $TOTAL"
echo "   Successfully Generated: $SUCCESS"
echo "   Failed: $FAILED"
echo ""
echo "📁 Examples created in:"
echo "   $EXAMPLES_DIR/"
echo ""
echo "📚 Next steps:"
echo "   1. Review CONNECTOR_CATALOG.md for full list"
echo "   2. Customize JSON files with your credentials"
echo "   3. Use with terraform-cloud-connector.sh"
echo ""
