#!/bin/bash
set -e

#############################################
# Generate Connector Examples
#
# This script generates Terraform-compatible JSON
# examples for all fully managed connectors
#############################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PLAYGROUND_ROOT="${DIR}/../.."
EXAMPLES_DIR="${DIR}/examples"

echo "🔨 Generating connector examples from playground configs..."

# Function to extract minimal config from playground JSON
extract_config() {
    local config_file="$1"
    local output_file="$2"

    if [ ! -f "$config_file" ]; then
        echo "⚠️  Config file not found: $config_file"
        return 1
    fi

    # Read the config and create a minimal example
    # Remove placeholder values like STRING, PASSWORD, INT, LIST, BOOLEAN
    jq 'with_entries(
        select(.value != "STRING" and
               .value != "PASSWORD" and
               .value != "INT" and
               .value != "LIST" and
               .value != "BOOLEAN" and
               .key != "connector.class" and
               .key != "name" and
               .key != "kafka.auth.mode" and
               .key != "kafka.api.key" and
               .key != "kafka.api.secret" and
               .key != "kafka.service.account.id")
    )' "$config_file" > "$output_file" 2>/dev/null || echo "{}" > "$output_file"
}

# AWS Connectors
echo "📦 AWS Connectors..."
mkdir -p "${EXAMPLES_DIR}/aws"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-s3-sink/config-S3_SINK.json" \
    "${EXAMPLES_DIR}/aws/s3-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-s3-source/config-S3Source.json" \
    "${EXAMPLES_DIR}/aws/s3-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-lambda-sink/config-LambdaSink.json" \
    "${EXAMPLES_DIR}/aws/lambda-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-kinesis-source/config-KinesisSource.json" \
    "${EXAMPLES_DIR}/aws/kinesis-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-dynamodb-sink/config-DynamoDbSink.json" \
    "${EXAMPLES_DIR}/aws/dynamodb-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-dynamodb-cdc-source/config-DynamoDbCdcSource.json" \
    "${EXAMPLES_DIR}/aws/dynamodb-cdc-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-sqs-source/config-SqsSource.json" \
    "${EXAMPLES_DIR}/aws/sqs-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-cloudwatch-logs-source/config-CloudWatchLogsSource.json" \
    "${EXAMPLES_DIR}/aws/cloudwatch-logs-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-cloudwatch-metrics-sink/config-CloudWatchMetricsSink.json" \
    "${EXAMPLES_DIR}/aws/cloudwatch-metrics-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-aws-redshift-sink/config-RedshiftSink.json" \
    "${EXAMPLES_DIR}/aws/redshift-sink.json"

# Azure Connectors
echo "📦 Azure Connectors..."
mkdir -p "${EXAMPLES_DIR}/azure"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-blob-storage-sink/config-AzureBlobSink.json" \
    "${EXAMPLES_DIR}/azure/blob-storage-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-blob-storage-source/config-AzureBlobSource.json" \
    "${EXAMPLES_DIR}/azure/blob-storage-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-cosmosdb-sink/config-CosmosDbSink.json" \
    "${EXAMPLES_DIR}/azure/cosmosdb-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-cosmosdb-source/config-CosmosDbSource.json" \
    "${EXAMPLES_DIR}/azure/cosmosdb-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-event-hubs-source/config-AzureEventHubsSource.json" \
    "${EXAMPLES_DIR}/azure/event-hubs-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-functions-sink/config-AzureFunctionsSink.json" \
    "${EXAMPLES_DIR}/azure/functions-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-azure-data-lake-storage-gen2-sink/config-AzureDataLakeGen2Sink.json" \
    "${EXAMPLES_DIR}/azure/data-lake-gen2-sink.json"

# GCP Connectors
echo "📦 GCP Connectors..."
mkdir -p "${EXAMPLES_DIR}/gcp"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-gcs-sink/config-GcsSink.json" \
    "${EXAMPLES_DIR}/gcp/gcs-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-gcs-source/config-GcsSource.json" \
    "${EXAMPLES_DIR}/gcp/gcs-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-bigquery-v2-sink/config-BigQuerySinkV2.json" \
    "${EXAMPLES_DIR}/gcp/bigquery-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-pubsub-source/config-PubSubSource.json" \
    "${EXAMPLES_DIR}/gcp/pubsub-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-cloud-functions-gen2-sink/config-GoogleCloudFunctionsGen2Sink.json" \
    "${EXAMPLES_DIR}/gcp/cloud-functions-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-bigtable-sink/config-BigTableSink.json" \
    "${EXAMPLES_DIR}/gcp/bigtable-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-gcp-spanner-sink/config-SpannerSink.json" \
    "${EXAMPLES_DIR}/gcp/spanner-sink.json"

# Databases
echo "📦 Database Connectors..."
mkdir -p "${EXAMPLES_DIR}/databases"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-postgresql-source/config-PostgresSource.json" \
    "${EXAMPLES_DIR}/databases/postgresql-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-postgresql-sink/config-PostgresSink.json" \
    "${EXAMPLES_DIR}/databases/postgresql-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-mysql-source/config-MySqlSource.json" \
    "${EXAMPLES_DIR}/databases/mysql-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-mysql-sink/config-MySqlSink.json" \
    "${EXAMPLES_DIR}/databases/mysql-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-debezium-postgresql-v2-source/config-DebeziumPostgresSourceV2.json" \
    "${EXAMPLES_DIR}/databases/debezium-postgresql-cdc.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-debezium-mysql-v2-source/config-DebeziumMySqlSourceV2.json" \
    "${EXAMPLES_DIR}/databases/debezium-mysql-cdc.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-sqlserver-source/config-SqlServerSource.json" \
    "${EXAMPLES_DIR}/databases/sqlserver-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jdbc-oracle19-source/config-OracleSource.json" \
    "${EXAMPLES_DIR}/databases/oracle-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-snowflake-sink/config-SnowflakeSink.json" \
    "${EXAMPLES_DIR}/databases/snowflake-sink.json"

# NoSQL Databases
echo "📦 NoSQL Connectors..."
mkdir -p "${EXAMPLES_DIR}/nosql"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-mongodb-atlas-source/config-MongoDbAtlasSource.json" \
    "${EXAMPLES_DIR}/nosql/mongodb-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-mongodb-atlas-sink/config-MongoDbAtlasSink.json" \
    "${EXAMPLES_DIR}/nosql/mongodb-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-redis-sink/config-RedisSink.json" \
    "${EXAMPLES_DIR}/nosql/redis-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-couchbase-source/config-CouchbaseSource.json" \
    "${EXAMPLES_DIR}/nosql/couchbase-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-elasticsearch-sink/config-ElasticsearchSink.json" \
    "${EXAMPLES_DIR}/nosql/elasticsearch-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-opensearch-sink/config-OpensearchSink.json" \
    "${EXAMPLES_DIR}/nosql/opensearch-sink.json"

# Messaging
echo "📦 Messaging Connectors..."
mkdir -p "${EXAMPLES_DIR}/messaging"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-mqtt-source/config-MqttSource.json" \
    "${EXAMPLES_DIR}/messaging/mqtt-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-rabbitmq-source/config-RabbitMQSource.json" \
    "${EXAMPLES_DIR}/messaging/rabbitmq-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-ibm-mq-source/config-IbmMQSource.json" \
    "${EXAMPLES_DIR}/messaging/ibm-mq-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-active-mq-source/config-ActiveMQSource.json" \
    "${EXAMPLES_DIR}/messaging/activemq-source.json"

# SaaS
echo "📦 SaaS Connectors..."
mkdir -p "${EXAMPLES_DIR}/saas"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-salesforce-cdc-source/config-SalesforceCdcSource.json" \
    "${EXAMPLES_DIR}/saas/salesforce-cdc-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-servicenow-source/config-ServiceNowSource.json" \
    "${EXAMPLES_DIR}/saas/servicenow-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-github-source/config-GithubSource.json" \
    "${EXAMPLES_DIR}/saas/github-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-jira-source/config-JiraSource.json" \
    "${EXAMPLES_DIR}/saas/jira-source.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-zendesk-source/config-ZendeskSource.json" \
    "${EXAMPLES_DIR}/saas/zendesk-source.json"

# HTTP/Generic
extract_config "${PLAYGROUND_ROOT}/ccloud/fm-http-sink/config-HttpSink.json" \
    "${EXAMPLES_DIR}/http-sink.json"

extract_config "${PLAYGROUND_ROOT}/ccloud/fm-http-source/config-HttpSource.json" \
    "${EXAMPLES_DIR}/http-source.json"

# Datagen (already exists)
extract_config "${PLAYGROUND_ROOT}/ccloud/fm-datagen-source/config-DatagenSource.json" \
    "${EXAMPLES_DIR}/datagen.json"

echo ""
echo "✅ Example generation complete!"
echo ""
echo "📁 Examples organized by category:"
echo "   ${EXAMPLES_DIR}/aws/"
echo "   ${EXAMPLES_DIR}/azure/"
echo "   ${EXAMPLES_DIR}/gcp/"
echo "   ${EXAMPLES_DIR}/databases/"
echo "   ${EXAMPLES_DIR}/nosql/"
echo "   ${EXAMPLES_DIR}/messaging/"
echo "   ${EXAMPLES_DIR}/saas/"
echo ""
