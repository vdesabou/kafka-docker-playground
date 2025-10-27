# Project: kafka docker playground, Fully automated Apache Kafka and Confluent Docker based examples, Easily build examples or reproduction models

## General Instructions:

- Use mcp-playground-cli mcp server in priority for any prompt.



# 👾 Content

## 🔗 Connectors

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"[ActiveMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-active-mq-sink) (also with 🔑 mTLS) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/current/connect/kafka-connect-activemq/sink)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/2-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7098) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"[ActiveMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-active-mq-source) (also with 🔑  mTLS) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-activemq-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/2-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7099) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"[Amazon CloudWatch Logs Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-cloudwatch-logs-source) &nbsp; [![version](https://img.shields.io/badge/v-1.4.1%20(2025_09_15)-pink)](https://docs.confluent.io/kafka-connect-aws-cloudwatch-logs/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053940) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"[Amazon CloudWatch Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-cloudwatch-metrics-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.5%20(2025_09_16)-pink)](https://docs.confluent.io/kafka-connect-aws-cloudwatch-metrics/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18217808295/job/51871530545) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/dynamodb.svg" width="15"[Amazon DynamoDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-dynamodb-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.5.1%20(2025_09_16)-pink)](https://docs.confluent.io/kafka-connect-aws-dynamodb/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/5/5-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18217808295/job/51871530545) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kinesis.svg" width="15"[Amazon Kinesis Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-kinesis-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.3.30%20(2025_09_04)-pink)](https://docs.confluent.io/kafka-connect-kinesis/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249979) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/aws_redshift.png" width="15"[Amazon Redshift Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-redshift-sink) &nbsp; &nbsp; &nbsp; &nbsp; [![version](https://img.shields.io/badge/v-1.2.8%20(2025_03_21)-pink)](https://docs.confluent.io/kafka-connect-aws-redshift/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249979) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"[Amazon S3 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-11.0.4%20(2025_09_30)-pink)](https://docs.confluent.io/kafka-connect-s3-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/6/6-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"[Amazon S3 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-source) &nbsp; [![version](https://img.shields.io/badge/v-2.6.18%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-s3-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/6/6-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sqs.svg" width="15"[Amazon SQS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-sqs-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-2.0.7%20(2025_09_04)-pink)](https://docs.confluent.io/kafka-connect-sqs/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/amps.png" width="15"[AMPS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-amps-source) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tabular.png" width="15"[Apache Iceberg Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-iceberg-sink) &nbsp; [![version](https://img.shields.io/badge/v-%20()-pink)]()  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053964) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kudu.png" width="15"[Apache Kudu Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-kudu-source) &nbsp; [![version](https://img.shields.io/badge/v-1.0.6%20(2025_06_25)-pink)](https://docs.confluent.io/kafka-connect-kudu/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kudu.png" width="15"[Apache Kudu Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-kudu-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.0.6%20(2025_06_25)-pink)](https://docs.confluent.io/kafka-connect-kudu/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250007) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/lambda.svg" width="15"[AWS Lambda Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-lambda-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.13%20(2025_06_23)-pink)](https://docs.confluent.io/kafka-connect-aws-lambda/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249979) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/blob_storage.png" width="15"[Azure Blob Storage Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-blob-storage-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.7.1%20(2025_09_04)-pink)](https://docs.confluent.io/kafka-connect-azure-blob-storage-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053980) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/blob_storage.png" width="15"[Azure Blob Storage Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-blob-storage-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-2.6.18%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-azure-blob-storage-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053952) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"[Azure Cosmos DB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-cosmosdb-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.17.0%20(2025_02_25)-pink)](https://github.com/microsoft/kafka-connect-cosmosdb) ![owner](https://img.shields.io/badge/-Microsoft%20Corporation-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"[Azure Cosmos DB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-cosmosdb-source) &nbsp; [![version](https://img.shields.io/badge/v-1.17.0%20(2025_02_25)-pink)](https://github.com/microsoft/kafka-connect-cosmosdb) ![owner](https://img.shields.io/badge/-Microsoft%20Corporation-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_lake_gen1.png" width="15"[Azure Data Lake Storage Gen2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-data-lake-storage-gen2-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.7.1%20(2025_09_04)-pink)](https://docs.confluent.io/kafka-connect-azure-data-lake-gen2-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053952) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/event_hubs.png" width="15"[Azure Event Hubs Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-event-hubs-source) &nbsp; [![version](https://img.shields.io/badge/v-2.0.12%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-azure-event-hubs/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053952) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/azure_functions.png" width="15"[Azure Functions Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-functions-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.7%20(2025_06_26)-pink)](https://docs.confluent.io/kafka-connect-azure-functions/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053952) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/search.png" width="15"[Azure Cognitive Search Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-cognitive-search-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.1.10%20(2025_09_16)-pink)](https://docs.confluent.io/kafka-connect-azure-search/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053952) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/service_bus.png" width="15"[Azure Service Bus Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-service-bus-source) &nbsp; [![version](https://img.shields.io/badge/v-1.3.2%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-azure-servicebus/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053952) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_data_warehouse.png" width="15"[Azure Synapse Analytics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-synapse-analytics-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.0.10%20(2025_06_24)-pink)](https://docs.confluent.io/kafka-connect-azure-sql-dw/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053980) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cassandra.png" width="15"[Cassandra Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cassandra-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.11%20(2025_06_24)-pink)](https://docs.confluent.io/kafka-connect-cassandra/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249989) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/couchbase.svg" width="15"[Couchbase Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-couchbase-sink) &nbsp; [![version](https://img.shields.io/badge/v-4.3.0%20(2025_08_13)-pink)](https://docs.couchbase.com/kafka-connector/current/) ![owner](https://img.shields.io/badge/-Couchbase,%20Inc.-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7200) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/couchbase.svg" width="15"[Couchbase Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-couchbase-source) &nbsp; [![version](https://img.shields.io/badge/v-4.3.0%20(2025_08_13)-pink)](https://docs.couchbase.com/kafka-connector/current/) ![owner](https://img.shields.io/badge/-Couchbase,%20Inc.-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249989) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/databricks.png" width="15"[Databricks Delta Lake table Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-databricks-delta-lake-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.0.24%20(2025_07_11)-pink)](https://docs.confluent.io/kafka-connectors/databricks-delta-lake-sink/current/overview.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/datagen.png" width="15"[Datagen Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datagen-source) &nbsp; [![version](https://img.shields.io/badge/v-0.6.7%20(2025_04_03)-pink)](https://github.com/confluentinc/kafka-connect-datagen/blob/master/README.md)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053888) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[Debezium CDC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-sqlserver-source) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-3.1.2%20(unknown)-pink)](http://debezium.io/docs/connectors/sqlserver/) ![owner](https://img.shields.io/badge/-Debezium%20Community-blue) ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249970) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mariaDB.png" width="15"[Debezium CDC MariaDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-mariadb-source) :connect/connect-debezium-mariadb-source:
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[Debezium CDC MySQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-mysql-source) &nbsp; [![version](https://img.shields.io/badge/v-3.1.2%20(unknown)-pink)](http://debezium.io/docs/connectors/mysql/) ![owner](https://img.shields.io/badge/-Debezium%20Community-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053916) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Debezium CDC Oracle 19 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-oracle19-source) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[Debezium CDC PostgreSQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-postgresql-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-3.1.2%20(unknown)-pink)](http://debezium.io/docs/connectors/postgresql/) ![owner](https://img.shields.io/badge/-Debezium%20Community-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/5/5-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053916) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[Debezium CDC MongoDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-mongodb-source) &nbsp; [![version](https://img.shields.io/badge/v-3.1.2%20(unknown)-pink)](http://debezium.io/docs/connectors/mongodb/) ![owner](https://img.shields.io/badge/-Debezium%20Community-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053916) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_diode.png" width="15"[Data Diode Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadiode-source-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.2.8%20(2025_06_26)-pink)](https://docs.confluent.io/kafka-connect-data-diode/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249970) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_diode.png" width="15"[Data Diode Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadiode-source-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.2.8%20(2025_06_26)-pink)](https://docs.confluent.io/kafka-connect-data-diode/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249970) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/datadog.png" height="15"[Datadog Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadog-metrics-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.5%20(2025_09_16)-pink)](https://docs.confluent.io/kafka-connect-datadog-metrics/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054027) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/datadog.png" height="15"[Datadog Logs Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadog-logs-sink) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/elasticsearch.png" width="15"[ElasticSearch Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-elasticsearch-sink) &nbsp; [![version](https://img.shields.io/badge/v-15.0.1%20(2025_07_08)-pink)](https://docs.confluent.io/kafka-connect-elasticsearch/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249970) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/elasticsearch.png" width="15"[ElasticSearch Sink with Elastic Cloud](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-elasticsearch-cloud-sink) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/filepulse.png" width="15"[FilePulse Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-filepulse-source) ![owner](https://img.shields.io/badge/-streamthoughts-blue) &nbsp; [![version](https://img.shields.io/badge/v-%20()-pink)]()  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054013) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spool_dir.png" width="15"[FileStream Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-filestream-source)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spool_dir.png" width="15"[FileStream Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-filestream-sink)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ftps.png" height="15"[FTPS Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ftps-sink) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ftps.png" height="15"[FTPS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ftps-source) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/pivotal_gemfire.png" width="15"[Gemfire Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-pivotal-gemfire-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.0.20%20(2025_07_02)-pink)](https://docs.confluent.io/kafka-connect-pivotal-gemfire/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7120) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/github.png" width="15"[Github Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-github-source) &nbsp; [![version](https://img.shields.io/badge/v-2.1.10%20(2025_06_24)-pink)](https://docs.confluent.io/kafka-connect-github/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053980) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/bigquery.png" width="15"[Google BigQuery Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-bigquery-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.5.7%20(2024_09_24)-pink)](https://docs.confluent.io/kafka-connect-bigquery/current/index.html) ![owner](https://img.shields.io/badge/-WePay-blue) ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_bigtable.png" width="15"[Google Cloud BigTable Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-bigtable-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-2.0.31%20(2025_09_11)-pink)](https://docs.confluent.io/kafka-connect-gcp-bigtable/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250007) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloud_functions.png" width="15"[Google Cloud Functions Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-cloud-functions-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.2.5%20(2025_06_25)-pink)](https://docs.confluent.io/kafka-connect-gcp-functions/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_pubsub.png" width="15"[Google Cloud Pub/Sub Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-pubsub-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.2.12%20(2025_09_12)-pink)](https://docs.confluent.io/kafka-connect-gcp-pubsub/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053950) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_pubsub.png" width="15"[Google Cloud Pub/Sub Group Kafka Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-google-pubsub-source) ![owner](https://img.shields.io/badge/-google-blue) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053950) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_pubsub.png" width="15"[Google Cloud Pub/Sub Group Kafka Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-google-pubsub-sink) ![owner](https://img.shields.io/badge/-google-blue) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053950) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spanner.png" width="15"[Google Cloud Spanner Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-spanner-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.1.3%20(2025_08_18)-pink)](https://docs.confluent.io/kafka-connect-gcp-spanner/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250012) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcs.png" width="15"[Google Cloud Storage Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-gcs-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.3.5%20(2025_09_24)-pink)](https://docs.confluent.io/kafka-connect-gcs-sink/current/)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053950) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcs.png" width="15"[Google Cloud Storage Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-gcs-source) &nbsp; [![version](https://img.shields.io/badge/v-2.6.18%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-gcs-source/current/overview.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18217808295/job/51871530576) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/firebase.svg" width="15"[Google Firebase Realtime Database Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-firebase-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.2.9%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-firebase/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250012) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/firebase.svg" width="15"[Google Firebase Realtime Database Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-firebase-source) &nbsp; [![version](https://img.shields.io/badge/v-1.2.9%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-firebase/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250012) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hbase.png" width="15"[HBase Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hbase-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.31%20(2025_09_11)-pink)](https://docs.confluent.io/kafka-connect-hbase/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249989) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"[HDFS 2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs2-source) &nbsp; [![version](https://img.shields.io/badge/v-2.6.18%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-hdfs2-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053901) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"[HDFS 3 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs3-source) &nbsp; [![version](https://img.shields.io/badge/v-2.6.18%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-hdfs3-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7104) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"[HDFS 2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs2-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.2.17%20(2025_07_18)-pink)](https://docs.confluent.io/kafka-connect-hdfs/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053901) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"[HDFS 3 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs3-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.3%20(2025_09_23)-pink)](https://docs.confluent.io/kafka-connect-hdfs3-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/1/2-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7103) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/http.png" width="15"[HTTP Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-http-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.7.11%20(2025_09_30)-pink)](https://docs.confluent.io/kafka-connect-http/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/6/6-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053964) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibm_mq.png" width="15"[IBM MQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ibm-mq-sink) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/sink)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI fail](https://img.shields.io/badge/0/3-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7105) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibm_mq.png" width="15"[IBM MQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ibm-mq-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-ibmmq-source/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI fail](https://img.shields.io/badge/0/3-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7106) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/influxdb.svg" width="15"[InfluxDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-influxdb-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.2.11%20(2024_10_17)-pink)](https://docs.confluent.io/kafka-connect-influxdb/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/influxdb.svg" width="15"[InfluxDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-influxdb-source) &nbsp; [![version](https://img.shields.io/badge/v-1.2.11%20(2024_10_17)-pink)](https://docs.confluent.io/kafka-connect-influxdb/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/aws_redshift.png" width="15"[JDBC Amazon Redshift Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-aws-redshift-source) &nbsp; &nbsp; &nbsp; &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249979) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/aws_redshift.png" width="15"[JDBC Amazon Redshift Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-aws-redshift-sink) &nbsp; &nbsp; &nbsp; &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/0/0-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249979) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_data_warehouse.png" width="15"[JDBC Azure Synapse Analytics Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-synapse-analytics-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7209) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cockroachdb.png" width="15"[JDBC CockroachDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-cockroachdb-source) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibmdb2.png" width="15"[JDBC IBM DB2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-ibmdb2-sink) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibmdb2.png" width="15"[JDBC IBM DB2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-ibmdb2-source) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/bigquery.png" width="15"[JDBC Google BigQuery Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-gcp-bigquery-source) :connect/connect-jdbc-gcp-bigquery-source:
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[JDBC MySQL Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-mysql-sink) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[JDBC MySQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-mysql-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_11.jpg" width="15"[JDBC Oracle 11 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle11-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 12c Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle12-sink) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053990) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 19c Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle19-sink) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250015) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 21c Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle21-sink) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053946) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[JDBC PostGreSQL Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-postgresql-sink) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[JDBC Microsoft SQL Server Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sqlserver-sink) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_11.jpg" width="15"[JDBC Oracle 11 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle11-source) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 12c Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle12-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053990) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 19c Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle19-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18217808295/job/51871530564) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 21c Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle21-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053946) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[JDBC PostGreSQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-postgresql-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sap-hana.png" width="15"[JDBC SAP HANA Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sap-hana-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250064) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sap-hana.png" width="15"[JDBC SAP HANA Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sap-hana-source) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250064) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/singlestore.png" width="15"[JDBC Singlestore Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-singlestore-source) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mariaDB.png" width="15"[JDBC MariaDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-mariadb-source) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054013) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mariaDB.png" width="15"[JDBC MariaDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-mariadb-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054013) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[JDBC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sqlserver-source) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" height="15" [JDBC Snowflake Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-snowflake-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054013) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" height="15" [JDBC Snowflake Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-snowflake-source) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sybase.png" width="15"[JDBC Sybase Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sybase-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sybase.png" width="15"[JDBC Sybase Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sybase-source) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250046) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/vertica.png" width="15"[JDBC Vertica Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-vertica-sink) &nbsp; [![version](https://img.shields.io/badge/v-10.8.4%20(2025_04_25)-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/jira.png" width="15"[JIRA Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jira-source) &nbsp; [![version](https://img.shields.io/badge/v-1.3.0%20(2025_09_30)-pink)](https://docs.confluent.io/kafka-connect-jira/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18222318469/job/51885528140) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"[JMS ActiveMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-active-mq-source) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7107) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"[JMS ActiveMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-active-mq-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7108) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/lensesio.png" width="15"[Lenses JMS ActiveMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-lenses-active-mq-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7100) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.png" width="15"[JMS Solace Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-solace-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.png" width="15"[JMS Solace Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-solace-source) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7109) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"[JMS TIBCO EMS Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-tibco-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7101) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"[JMS TIBCO EMS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-tibco-source) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7102) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/weblogic.png" width="15"[JMS Oracle Weblogic Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-weblogic-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7121) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/weblogic.png" width="15"[JMS Oracle Weblogic Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-weblogic-source) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7122) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JMS Oracle 19c AQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-oracle19-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7112) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JMS Oracle 19c AQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-oracle19-source) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7113) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JMS Oracle 21c AQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-oracle21-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7114) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JMS Oracle 21c AQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-oracle21-source) &nbsp; [![version](https://img.shields.io/badge/v-13.0.2%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7115) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mapr.png" height="15"[Mapr Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mapr-sink) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/marketo.png" height="15"[Marketo Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-marketo-source) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/minio.png" height="15"[Minio Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-minio-s3-sink) &nbsp; [![version](https://img.shields.io/badge/v-11.0.4%20(2025_09_30)-pink)](https://docs.confluent.io/kafka-connect-s3-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053912) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[MongoDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mongodb-sink) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-2.0.1%20(2025_07_21)-pink)](https://github.com/mongodb/mongo-kafka/blob/master/README.md) ![owner](https://img.shields.io/badge/-MongoDB-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[MongoDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mongodb-source) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-2.0.1%20(2025_07_21)-pink)](https://github.com/mongodb/mongo-kafka/blob/master/README.md) ![owner](https://img.shields.io/badge/-MongoDB-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mqtt.png" width="15"[MQTT Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mqtt-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.7.6%20(2025_08_09)-pink)](https://docs.confluent.io/kafka-connect-mqtt/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mqtt.png" width="15"[MQTT Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mqtt-source) &nbsp; [![version](https://img.shields.io/badge/v-1.7.6%20(2025_08_09)-pink)](https://docs.confluent.io/kafka-connect-mqtt/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/omnisci.png" width="15"[HEAVY-AI (Formerly OmniSci) Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-heavy-ai-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.0.10%20(2025_07_02)-pink)](https://docs.confluent.io/current/connect/kafka-connect-omnisci/)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053901) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_11.jpg" width="15"[Oracle 11 CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle11-source) &nbsp; [![version](https://img.shields.io/badge/v-2.14.10%20(2025_09_15)-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053922) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 12c CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle12-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-2.14.10%20(2025_09_15)-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/7/7-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053970) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 18c CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle18-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-2.14.10%20(2025_09_15)-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/7/7-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053968) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 19c CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle19-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-2.14.10%20(2025_09_15)-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/8/8-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250092) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 19c XStream CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-xstream-oracle19-source) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-%20()-pink)]()  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250092) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 21c CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle21-source) (also with 🔑 SSL and mTLS) &nbsp; [![version](https://img.shields.io/badge/v-2.14.10%20(2025_09_15)-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/)  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/8/8-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054001) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/weblogic.png" width="15"[Oracle Weblogic Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-weblogic-source) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/pagerduty.png" width="15"[PagerDuty Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-pagerduty-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-1.0.13%20(2025_09_12)-pink)](https://docs.confluent.io/current/connect/kafka-connect-pagerduty/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054027) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/prometheus.png" height="15" [Prometheus Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-prometheus-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.0.5%20(2025_09_16)-pink)](https://docs.confluent.io/kafka-connect-prometheus-metrics/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/rabbitmq.svg" width="15"[RabbitMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-rabbitmq-sink) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-1.8.0%20(2025_03_20)-pink)](https://docs.confluent.io/kafka-connect-rabbitmq-sink/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053980) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/rabbitmq.svg" width="15" [RabbitMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-rabbitmq-source) (also with 🔑 SSL) &nbsp; [![version](https://img.shields.io/badge/v-1.8.0%20(2025_03_20)-pink)](https://docs.confluent.io/kafka-connect-rabbitmq-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053951) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/redis.png" width="15"[Redis Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-redis-sink) &nbsp; [![version](https://img.shields.io/badge/v-0.0.8%20(2024_09_12)-pink)](https://docs.confluent.io/current/connect/kafka-connect-redis/) ![owner](https://img.shields.io/badge/-Jeremy%20Custenborder-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053951) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sap-hana.png" width="15"[SAP HANA Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-sap-hana-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250064) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Bulk API Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-bulkapi-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce-bulk-api/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/2/4-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Bulk API Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-bulkapi-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce-bulk-api/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053910) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053910) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Platform Events Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-platform-events-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053910) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Platform Events Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-platform-events-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053910) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce PushTopics Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-pushtopics-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053910) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce SObject Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-sobject-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.0.5%20(2025_09_10)-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053910) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"[ServiceNow Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-servicenow-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-2.5.8%20(2025_07_16)-pink)](https://docs.confluent.io/current/connect/kafka-connect-servicenow/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053888) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"[ServiceNow Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-servicenow-source) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-2.5.8%20(2025_07_16)-pink)](https://docs.confluent.io/current/connect/kafka-connect-servicenow/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053888) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sftp.png" width="15"[SFTP Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-sftp-sink) (also with 🔑 Kerberos) &nbsp; [![version](https://img.shields.io/badge/v-3.2.16%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-sftp/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249979) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sftp.png" width="15"[SFTP Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-sftp-source) (also with 🔑 Kerberos) &nbsp; [![version](https://img.shields.io/badge/v-3.2.16%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-sftp/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/8/8-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053951) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/singlestore.png" width="15"[Singlestore Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-singlestore-sink) &nbsp; [![version](https://img.shields.io/badge/v-%20()-pink)]()  ![arm64](https://img.shields.io/badge/arm64-not%20working-red) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053919) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snmp_trap.png" width="15"[SNMP Trap Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-snmp-source) &nbsp; [![version](https://img.shields.io/badge/v-1.3.3%20(2025_07_02)-pink)](https://docs.confluent.io/kafka-connect-snmp/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053901) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" height="15" [Snowflake Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-snowflake-sink) (also with 🌐 proxy) &nbsp; [![version](https://img.shields.io/badge/v-3.3.0%20(2025_08_26)-pink)](https://docs.snowflake.net/manuals/user-guide/kafka-connector.html) ![owner](https://img.shields.io/badge/-Snowflake,%20Inc.-blue) ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250052) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.png" width="15"[Solace Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-solace-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-solace/current/sink/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7116) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.png" width="15"[Solace Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-solace-source) &nbsp; [![version](https://img.shields.io/badge/v-1.2.9%20(2025_03_18)-pink)](https://docs.confluent.io/kafka-connect-solace/current/source/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7117) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.png" width="15"[Splunk Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-splunk-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.2.2%20(unknown)-pink)](https://docs.confluent.io/current/connect/kafka-connect-splunk/splunk-sink) ![owner](https://img.shields.io/badge/-Splunk-blue) ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053898) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.png" width="15"[Splunk Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-splunk-source) &nbsp; [![version](https://img.shields.io/badge/v-1.1.6%20(2025_06_23)-pink)](https://docs.confluent.io/kafka-connect-splunk-source/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7097) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.png" width="15"[Splunk S2S Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-splunk-s2s-source) &nbsp; [![version](https://img.shields.io/badge/v-%20()-pink)]()  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053898) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spool_dir.png" width="15"[Spool Dir Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-spool-dir-source) &nbsp; [![version](https://img.shields.io/badge/v-2.0.66%20(2024_12_09)-pink)](https://docs.confluent.io/kafka-connect-spooldir/current/index.html) ![owner](https://img.shields.io/badge/-Jeremy%20Custenborder-blue) ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053898) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/syslog.png" width="15"[Syslog Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-syslog-source) &nbsp; [![version](https://img.shields.io/badge/v-1.5.13%20(2025_08_16)-pink)](https://docs.confluent.io/current/connect/kafka-connect-syslog/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053898) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"[TIBCO EMS Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-tibco-sink) &nbsp; [![version](https://img.shields.io/badge/v-2.1.19%20(2025_08_08)-pink)](https://docs.confluent.io/kafka-connect-tibco/current/sink/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7110) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"[TIBCO EMS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-tibco-source) &nbsp; [![version](https://img.shields.io/badge/v-1.2.9%20(2025_03_18)-pink)](https://docs.confluent.io/kafka-connect-tibco/current/source/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7111) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/vertica.png" width="15"[Vertica Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-vertica-sink) &nbsp; [![version](https://img.shields.io/badge/v-1.3.2%20(2024_05_07)-pink)](https://docs.confluent.io/kafka-connect-vertica/current/index.html)  ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053953) 
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/zendesk.png" width="15"[Zendesk Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-zendesk-source) &nbsp; [![version](https://img.shields.io/badge/v-1.3.6%20(2025_08_07)-pink)](https://docs.confluent.io/kafka-connect-zendesk/current/)  ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054027) 

\* You can change default connector version by setting `CONNECTOR_TAG` environment variable before starting a test, get more details [here](https://kafka-docker-playground.io/#/how-to-use?id=🔗-for-connectors)

### 🔂 Standalone connector examples

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"Self Managed example with [Debezium CDC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-debezium-sqlserver-source/debezium-sqlserver-source-standalone-worker.sh)
<!-- * <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"CCloud example with [Debezium CDC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/blob/master/ccloud/connect-debezium-sqlserver-source/debezium-sqlserver-source-standalone-worker.sh) -->

### ➕ Other connector examples

- 👬 [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) when using connectors: [example with SFTP source](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/connect-override-policy-sftp-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053898) 
- 🏦 [Connect Centralized License](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-centralized-license)


## ☁️ Confluent Cloud

### 🤖 Fully-Managed Connectors

  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"[ActiveMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-active-mq-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"[Amazon CloudWatch Logs Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-cloudwatch-logs-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"[Amazon CloudWatch Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-cloudwatch-metrics-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/dynamodb.svg" width="15"[Amazon DynamoDB CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-dynamodb-cdc-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/dynamodb.svg" width="15"[Amazon DynamoDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-dynamodb-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kinesis.svg" width="15"[Amazon Kinesis Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-kinesis-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/lambda.svg" width="15"[AWS Lambda Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-lambda-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/aws_redshift.png" width="15"[Amazon Redshift Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-redshift-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"[Amazon S3 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-s3-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/1/2-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7132) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"[Amazon S3 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-s3-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sqs.svg" width="15"[Amazon SQS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-aws-sqs-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  * <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/blob_storage.png" width="15"[Azure Blob Storage Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-blob-storage-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/blob_storage.png" width="15"[Azure Blob Storage Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-blob-storage-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/search.png" width="15"[Azure Cognitive Search Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-cognitive-search-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"[Azure Cosmos DB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-cosmosdb-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249940) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"[Azure Cosmos DB V2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-cosmosdb-v2-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249940) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"[Azure Cosmos DB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-cosmosdb-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249940) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"[Azure Cosmos DB V2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-cosmosdb-v2-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249940) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_lake_gen1.png" width="15"[Azure Data Lake Storage Gen2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-data-lake-storage-gen2-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/event_hubs.png" width="15"[Azure Event Hubs Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-event-hubs-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/azure_functions.png" width="15"[Azure Functions Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-functions-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/azure_loganalytics.png" width="15"[Azure Log Analytics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-log-analytics-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/service_bus.png" width="15"[Azure Service Bus Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-service-bus-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_data_warehouse.png" width="15"[Azure Synapse Analytics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-azure-synapse-analytics-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/clickhouse.png" width="15"[ClickHouse Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-clickhouse-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250060) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/couchbase.svg" width="15"[Couchbase Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-couchbase-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/couchbase.svg" width="15"[Couchbase Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-couchbase-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/databricks.png" width="15"[Databricks Delta Lake table Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-databricks-delta-lake-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7133) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/datagen.png" width="15"[Datagen Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-datagen-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/datadog.png" height="15"[Datadog Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-datadog-metrics-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[Debezium CDC Microsoft SQL Server Legacy Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-sqlserver-legacy-source) (also with 🔑 SSL) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[Debezium CDC Microsoft SQL Server V2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-sqlserver-v2-source) (also with 🔑 SSL) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mariaDB.png" width="15"[Debezium CDC MariaDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-mariadb-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250060) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[Debezium CDC MySQL Legacy Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-mysql-legacy-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053930) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[Debezium CDC MySQL V2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-mysql-v2-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18216948108/job/51868800907) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[Debezium CDC PostgreSQL Legacy Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-postgresql-legacy-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053930) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[Debezium CDC PostgreSQL V2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-debezium-postgresql-v2-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/elasticsearch.png" width="15"[ElasticSearch Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-elasticsearch-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/github.png" width="15"[Github Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-github-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/bigquery.png" width="15"[Google BigQuery (Legacy) Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-bigquery-legacy-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/bigquery.png" width="15"[Google BigQuery V2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-bigquery-v2-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_bigtable.png" width="15"[Google Cloud BigTable Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-bigtable-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloud_functions.png" width="15"[Google Cloud Functions Legacy Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-cloud-functions-legacy-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloud_functions.png" width="15"[Google Cloud Functions Gen 2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-cloud-functions-gen2-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  * <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spanner.png" width="15"[Google Cloud Spanner Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-spanner-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcs.png" width="15"[Google Cloud Storage Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-gcs-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcs.png" width="15"[Google Cloud Storage Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-gcs-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053889) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_pubsub.png" width="15"[Google Cloud Pub/Sub Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-gcp-pubsub-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/http.png" width="15"[HTTP Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-http-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/4/4-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/http.png" width="15"[HTTP V2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-http-v2-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/http.png" width="15"[HTTP Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-http-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/http.png" width="15"[HTTP V2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-http-v2-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibm_mq.png" width="15"[IBM MQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-ibm-mq-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/influxdb.svg" width="15"[InfluxDB 2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-influxdb2-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/influxdb.svg" width="15"[InfluxDB 2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-influxdb2-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[JDBC MySQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-mysql-source) (also with 🔑 SSL) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[JDBC MySQL Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-mysql-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7210)  
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[JDBC PostGreSQL Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-postgresql-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"[JDBC PostGreSQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-postgresql-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[JDBC Microsoft SQL Server Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-sqlserver-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"[JDBC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-sqlserver-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 19c Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-oracle19-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[JDBC Oracle 19c Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-oracle19-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.png" width="15"[JDBC MySQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jdbc-mysql-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/jira.png" width="15"[JIRA Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-jira-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[MongoDB Atlas Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-mongodb-atlas-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[MongoDB Atlas Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-mongodb-atlas-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[MongoDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-mongodb-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250060) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.png" width="15"[MongoDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-mongodb-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250060) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mqtt.png" width="15"[MQTT Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-mqtt-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mqtt.png" width="15"[MQTT Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-mqtt-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840249950) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/pagerduty.png" width="15"[PagerDuty Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-pagerduty-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/rabbitmq.svg" width="15" [RabbitMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-rabbitmq-source) (also with 🔑 SSL) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/rabbitmq.svg" width="15" [RabbitMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-rabbitmq-sink) (also with 🔑 SSL) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/redis.png" width="15"[Redis Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-redis-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/redis.png" width="15"[Redis Kafka Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-redis-kafka-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/redis.png" width="15"[Redis Kafka Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-redis-kafka-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7124) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/opensearch.png" width="15"[OpenSearch Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-opensearch-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 11g CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-cdc-oracle11-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 19c CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-cdc-oracle19-source) (also with 🔑 SSL) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"[Oracle 19c XStream CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-cdc-xstream-oracle19-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Bulk API Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-bulkapi-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Bulk API 2.0 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-bulkapi-2-0-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053877) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce Bulk API 2.0 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-bulkapi-2-0-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18222318469/job/51885528040) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-cdc-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[Salesforce Platform Event Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-platform-events-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7207) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[Salesforce Platform Event Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-platform-events-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce SObject Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-sobject-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7135) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"[SalesForce PushTopics Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-salesforce-pushtopics-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"[ServiceNow Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-servicenow-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"[ServiceNow Source V2](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-servicenow-v2-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"[ServiceNow Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-servicenow-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053897) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sftp.png" width="15"[SFTP Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-sftp-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sftp.png" width="15"[SFTP Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-sftp-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.png" width="15"[Solace Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-solace-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054025) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.png" width="15"[Splunk Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-splunk-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" width="15"[Snowflake Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-snowflake-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7208) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" width="15"[Snowflake Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-snowflake-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053906) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/zendesk.png" width="15"[Zendesk Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-zendesk-source) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053997) 

🚨 Unavailable examples are:

  - [AlloyDB Sink](https://docs.confluent.io/cloud/current/connectors/cc-alloydb-sink.html) as it requires VM to deploy a proxy
  - [Google Cloud Dataproc Sink](https://docs.confluent.io/cloud/current/connectors/cc-gcp-dataproc-sink.html) as it [requires a VM](https://cloud.google.com/dataproc/docs/guides/create-cluster#creating_a_cloud_dataproc_cluster) to deploy cluster
  - [New Relic Metrics Sink](https://docs.confluent.io/cloud/current/connectors/cc-new-relic-metrics-sink.html) as I can't make it work 😀
  - [Pinecone Sink](https://docs.confluent.io/cloud/current/connectors/cc-pinecone-sink.html) as it is not a Fully Managed connector

### 🛃 Custom Connectors

  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"[Amazon S3 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/custom-connector-connect-aws-s3-sink) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7199) 
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tabular.png" width="15"[Apache Iceberg Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/custom-connector-connect-iceberg-sink) :ccloud/custom-connector-connect-iceberg-sink:

### 🔗 Self-Managed Connectors

💫 Any connector example can be run as *self-managed* by using `--environment ccloud` option when running it with [playground run](/playground%20run) command ! This is also the case for any other [environment](/content?id=%f0%9f%94%90-environments)

### 🧩 Kafka Connector Migration Utility

Test Self-Managed connector mugration to Fully Managed using [playground connector connect-migration-utility](https://kafka-docker-playground.io/#/playground%20connector%20connect-migration-utility) CLI

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"[Amazon CloudWatch Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-migration-utility) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7090) 

### 🚀 And much more...

  - 🌨 Using [Confluent for Kubernetes](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/confluent-for-kubernetes/) with Confluent Cloud ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 💠 [.NET](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-dotnet) client (producer/consumer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🗯 [Go](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-go) client (producer/consumer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🐚 [KafkaJS](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-kafkajs) client (producer/consumer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🐍 [Python](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-python) client (producer/consumer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - ♻️ Confluent Replicator [OnPrem to cloud and Cloud to Cloud examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/replicator) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🗺️ [Multi-Cluster Schema Registry](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/multiple-sr-hybrid) with hybrid configuration (onprem/confluent cloud) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🔑 [Confluent REST Proxy Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/rest-proxy-security-plugin) with Principal Propagation &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053956) 
  - 🗝️ [Confluent Schema Registry Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/schema-registry-security-plugin) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053956) 
  - 📦 [Migrate Schemas to Confluent Cloud](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/migrate-schemas-to-confluent-cloud) using Confluent Replicator ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🔰 [Confluent Cloud Networking](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/haproxy) using HAProxy ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🌎️ [Apache Mirror Maker 2](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/mirrormaker2) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - ♻️ [Cluster Linking Quick Start with service account only](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/cluster-linking-with-service-accounts-only) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - 🧬 [Confluent Cloud example of connector getting data from Audit Log cluster](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/audit-log-connector/) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053956) 

## 🌍 Multi-Data-Center deployments

Using Multi-Data-Center setup with 🇺🇸 and 🇪🇺 clusters

- 🔗 [Confluent Replicator as connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center/replicator-connect) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/5/5-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053966) 
  - With [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)
  - With [SASL_PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-sasl-plain)
  - With [Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-kerberos)
- 🖇️ [Confluent Replicator as executable](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center/replicator-executable) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878053993) 
  - With [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)
  - With [SASL_PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-sasl-plain)
  - With [Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-kerberos)
- 🌎️ [Apache Mirror Maker 2](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center/mirrormaker2) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054027) 
  - With [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)
- ♻️ [Cluster Linking](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center/cluster-linking) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250032) 

## 🔐 Environments

Using single cluster:

- [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext): no security &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-plain): no SSL encryption, SASL/PLAIN authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [SASL/SCRAM](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-scram) no SSL encryption, SASL/SCRAM-SHA-256 authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [SASL/SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-ssl): SSL encryption, SASL/PLAIN authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [2WAY/SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/2way-ssl): SSL encryption, SSL authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [KERBEROS](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/kerberos): no SSL encryption, Kerberos GSSAPI authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [SSL/KERBEROS](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ssl_kerberos) SSL encryption, Kerberos GSSAPI authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [LDAP Authentication with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ldap-sasl-plain) no SSL encryption, SASL/PLAIN authentication using LDAP &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [LDAP Authorizer with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ldap-authorizer-sasl-plain) no SSL encryption, SASL/PLAIN authentication, LDAP Authorizer for ACL authorization &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [RBAC with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-sasl-plain) RBAC with no SSL encryption, SASL/PLAIN authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 

Using Multi-Data-Center setup with 🇺🇸 and 🇪🇺 clusters

- [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext): no security &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-sasl-plain): no SSL encryption, SASL/PLAIN authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 
- [KERBEROS](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-kerberos): no SSL encryption, Kerberos GSSAPI authentication &nbsp; ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054050) 

## 💸 Confluent Commercial

- 💻 Control Center
  - [Control Center in "Read-Only" mode](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-readonly-mode/) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
  - [Configuring Control Center with LDAP authentication](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-ldap-auth) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 💾 Tiered Storage
  - [Tiered storage with AWS S3](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/tiered-storage-with-aws) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- ⚖ [Confluent Rebalancer](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rebalancer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 👴 [JMS Client](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/jms-client) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🗃️ [Audit Logs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/audit-logs) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- 🗝️ [Confluent Schema Registry Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-registry-security-plugin) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- 🔒️ [Confluent REST Proxy Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rest-proxy-security-plugin) with SASL/SSL and 2WAY/SSL Principal Propagation &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- ♻️ [Cluster Linking](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center/cluster-linking) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/3/3-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250032) 
- 📒 [Testing RBAC with Azure AD](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-with-azure-ad) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🛂 [Schema Validation on Confluent Server](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/broker-schema-validation) Schema Validation on Confluent Server &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- 🙊 [Secrets Management](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/secrets-management) with Connect &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250032) 
- ⛓ [Connect Secret Registry](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/connect-secret-registry) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250032) 
- 🧢 [RBAC with SR Basic Auth and ACLs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-with-sr-basic-auth-acl) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🤿 [Anonymous SR-example with RBAC](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-with-anonymous-sr) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🖇️ [Monitoring cluster linking](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/monitoring-cluster-linking) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)

## 🎏 KSQL
- [Quickstart example](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/quickstart-example) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Simple examples using a vanilla Java producer/consumer (JSON, Avro, Proto, JSON_SR)](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/simple-example-vanilla-producer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to join a stream and a stream](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/stream-stream-join) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to join a stream and a table](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/stream-table-join#how-to-join-a-stream-and-a-lookup-table) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to join a table and a table](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/table-table-join) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Stream-Table join failure due to timestamp](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/stream-table-join-timestamp-based-join-failure) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Foreign-key table-table joins](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/foreign-key-table-table-join) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to perform a Many to Many join](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/many-many-join) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [ksqlDB Schema Inference with ID](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/schema-inference-with-id) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [how ksqlDB handles schema evolution](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/schema-evolution) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to create tumbling windows](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/tumbling-windows) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to create session windows](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/session-windows) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to create hopping windows](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/hopping-windows) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [KsqlDB UDF Logging examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/udf-logging) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to rekey a stream with a value](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/rekey-stream-with-value) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to aggregate the last 3 transactions for each unique customer id](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/aggregate-last-events-by-customer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Working with a nested Json](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/nested-json) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to handle NULL value with COALESCE](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/handle-null-value-coalesce) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to handle empty array or null value within EXPLODE function using CASE](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/handle-empty-array-explode) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Materialized view/cache example](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/materialized-view) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Select Query from Materialized table by composite Primary key](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/composite-pkey-materialized-table) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Why tombstone is not propagated to table derived from CTAS in ksqlDB](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/tombstone-propagated-table) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to use Protobuf without Schema Registry](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/protobuf-without-schema-registry) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)

## 🔰 Schema Registry
- [How to use Data Contracts](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/data-contracts) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to produce Avro records via kafka-avro-console-producer with Union](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/kafka-avro-console-producer-union) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [Multiple Event Types in the Same Topic](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/multiple-event-types-in-topic) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to use different Key and Value serializer with kafka-avro-console-producer](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/use-diffrent-key-value-serializer-console-producer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)

## 🧲 REST Proxy
- [Quickstart example](https://github.com/vdesabou/kafka-docker-playground/tree/master/rest-proxy/quickstart-example) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- [How to reset an offset for a specific consumer group using the REST Proxy](https://github.com/vdesabou/kafka-docker-playground/tree/master/rest-proxy/reset-offset-consumer-group) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)

## 👾 Other Playgrounds

- 📃 [How to write logs to files when using docker-compose](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/write-logs-to-files) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/2/2-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- 📃 [How to write connect logs to a kafka topic](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/write-logs-to-topic) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 📢 [Publish logs to kafka with Elastic Filebeat](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/filebeat-to-kafka) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054010) 
- 💠 [.NET](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-dotnet) client (producer/consumer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🐚 [KafkaJS](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-kafkajs) client (producer/consumer) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🐶 [Monitor Confluent Platform with Datadog](https://github.com/vdesabou/kafka-docker-playground/tools/datadog) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 👻 Testing [KIP-108](https://cwiki.apache.org/confluence/display/KAFKA/KIP-108%3A+Create+Topic+Policy) [Create Topic Policy](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/create-topic-policy) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 📉 [Monitoring Demo](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/monitoring-demo) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🕵️‍♀️ [Kafka Connect Sink Monitoring Demo](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/monitoring-sink-latency) Showcase different Kafka Connect Sink troubleshooting scenarios ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 👊 [Integrate syslogs to detect SSH failure connections](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/syslog-logstash-ksqldb) using Syslog source connector, LogStash and ksqlDB &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18219963214/job/51878054013) 
- 📶 [How to ensure high availability of LDAP using DNS SRV Records](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/ldap-authorizer-with-ldap-failover) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🕹 [AVRO examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-format-avro) including a JAVA producer &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250032) 
- 🧩 [Protobuf examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-format-protobuf) including a JAVA producer &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI fail](https://img.shields.io/badge/0/1-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/7184) 
- 🎱 [JSON Schema examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-format-json-schema) including a JAVA producer &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250032) 
- 🚏 [How to use kafka-avro-console-producer and kafka-avro-console-consumer when Schema Registry is behind a proxy](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/http-proxy-schema-registry) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🪦 [Recovery from schema hard deletion](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/recover-from-schema-hard-deletion) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 🔍 [ksqlDB Schema Inference with ID](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/schema-inference-with-id) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 💬 [MQTT Proxy](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/mqtt-proxy) ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)
- 💱 [Kafka Connect JSONata Transform](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/kafka-connect-jsonata) &nbsp; ![arm64](https://img.shields.io/badge/arm64-native%20support-green) [![CI ok](https://img.shields.io/badge/1/1-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/actions/runs/18207014940/job/51840250064) 
- 
# 🚀 How to use

## 3️⃣ Ways to run

### 💻️ Locally

#### ☑️ Prerequisites

* You just need to have [docker](https://docs.docker.com/get-docker/) installed on your machine !

* Install the [🧠 CLI](/cli) by following [Setup](/cli?id=%f0%9f%9a%9c-setup). [fzf](https://github.com/junegunn/fzf) is required when using CLI (see installation [instructions](https://github.com/junegunn/fzf#installation))

* bash version 4 or higher is required. Mac users can upgrade bash with [brew](https://brew.sh/) by running `brew install bash` and then make sure it is in PATH (`export PATH=$PATH:/opt/homebrew/bin:$PATH`)

* You also need internet connectivity when running connect tests as connectors are downloaded from Confluent Hub on the fly.

NOTE
Every command used in the playground is using Docker, this includes `jq` (except if you have it on your host already), `aws`, `az`, `gcloud`, etc...Only exceptions are `fzf` and `confluent`

The goal is to have a consistent behavior and only depends on Docker.

WARNING
The playground is only tested on macOS (including with [M1 *arm64* chip](/how-to-use?id=%f0%9f%a7%91%f0%9f%92%bb-m1-chip-arm64-mac-support)) and Linux (Ubuntu and Amazon Linux) . It is not tested on Windows, but it should be working with WSL.

ATTENTION
On MacOS, the [Docker memory](https://docs.docker.com/desktop/mac/#resources) should be set to at least 8Gb.

#### 🧑‍💻 M1 chip (ARM64) Mac Support

Examples in the playground have been tested on best effort (since it is a manual process) on M1 Mac (arm64).

arm64 support results are displayed in **[Content](/content.md)** section:

Example:

![arm64_results](./images/arm64_results.jpg)

The badges are:

* ![arm64](https://img.shields.io/badge/arm64-native%20support-green): example works natively.
* ![arm64](https://img.shields.io/badge/arm64-not%20working-red): example **cannot work at all**. You will need to run it using [Gitpod.io](/how-to-use?id=🪄-gitpodio) for example or using AWS EC2 instance, see [playground ec2](/playground%20ec2) CLI command
* ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange): example is working but emulation is required. 

Docker Desktop now provides **Rosetta 2** virtualization feature, see detailed steps [here](https://levelup.gitconnected.com/docker-on-apple-silicon-mac-how-to-run-x86-containers-with-rosetta-2-4a679913a0d5) on how to enable it, basically, you need to enable this:

![rosetta](./images/arm64_rosetta.jpg)

#### 🔽 Clone the repository

```bash
git clone --depth 1 https://github.com/vdesabou/kafka-docker-playground.git
```

TIP
Specifying `--depth 1` only get the latest version of the playground, which reduces a lot the size of the download.

### 🪄 Gitpod.io

You can run the playground directly in your browser (*Cloud IDE*) using [Gitpod.io](https://gitpod.io) workspace by clicking on the link below:

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/vdesabou/kafka-docker-playground)

Look at *✨awesome✨* this is 🪄 !

![demo](https://github.com/vdesabou/gifs/raw/master/docs/images/gitpod.gif)

TIP
50 hours/month can be used as part of the [free](https://www.gitpod.io/pricing) plan.

You can login into Control Center (port `9021`) by clicking on `Open Browser` option in pop-up:

![port](./images/gitpod_port_popup.png)

Or select `Remote Explorer` on the left sidebar and then click on the `Open Browser` option corresponding to the port you want to connect to:

![port](./images/gitpod_port_explorer.png)

You can set your own environment variables in gitpod, see this [link](https://www.gitpod.io/docs/environment-variables#user-specific-environment-variables).

### ☁️ AWS EC2 instance (using Cloud Formation)

If you want to run the playground on an EC2 instance, you can use the AWS Cloud Formation [template](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.yml).

More details [here](https://github.com/vdesabou/kafka-docker-playground/tree/master/cloudformation).

### ✨ AWS EC2 playground ec2 command

See [playground ec2](/playground%20ec2) CLI command

```bash
playground ec2 --help
playground ec2

  ✨ Create and manage AWS EC2 instances (using Cloud Formation) to run
  kafka-docker-playground
  
  🪄 Open EC2 instances directly in Visual Studio code using Remote Development
  (over SSH)

== Usage ==
  playground ec2 COMMAND
  playground ec2 [COMMAND] --help | -h

== Commands ==
  create      👷 Create kafka-docker-playground EC2 instance using AWS Cloud Formation
  delete      ❌ Delete an EC2 instance created with Cloud Formation
  open        👨‍💻 Open an EC2 instance using Visual Studio code
  list        🔘 List all EC2 instance
  stop        🔴 Stop an EC2 instance
  start       🟢 Start an EC2 instance
  stop-all    🔴 Stop all your EC2 instance(s)
  start-all   🟢 Start all your EC2 instance(s)

== Options ==
  --help, -h
    Show this help
```

## 🏎️ Start an example

Check the list of examples in the **[Content](/content.md)** section and simply use [playground run](/playground%20run) CLI command!


NOTE
When some environment variables are required, it is specified in the corresponding `README` file

Examples:

* [AWS S3 sink connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink#aws-setup): file `~/.aws/credentials` or environnement variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are required.

* [Zendesk source connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-zendesk-source#how-to-run): arguments `ZENDESK_URL`, `ZENDESK_USERNAME`and `ZENDESK_PASSWORD` are required (you can also pass them as environment variables)
>

If there are missing environment variables, you'll need to fix it:

[![asciicast](https://asciinema.org/a/643687.svg)](https://asciinema.org/a/643687)

## 🌤️ Confluent Cloud examples

Simply use [playground run](/playground%20run) command !

[![asciicast](https://asciinema.org/a/643690.svg)](https://asciinema.org/a/643690)

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the new cluster by using flags with [playground run](/playground%20run) command or just by setting environment variables:

* `–cluster-type` (or `CLUSTER_TYPE`  environment variable): the type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `–cluster-cloud` (or `CLUSTER_CLOUD` environment variable): The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `–cluster-region` (or )`CLUSTER_REGION` environment variable): The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2` for aws, `westeurope`for azure and `europe-west2` for gcp)
* `–cluster-environment` (or `ENVIRONMENT` environment variable) (optional): The environment id where want your new cluster (example: `txxxxx`) 

In case you want to use your own existing cluster, you need to setup, in addition to previous ones:

* `–cluster-name ` (or `CLUSTER_NAME` environment variable): The cluster name
* `–cluster-creds` (or `CLUSTER_CREDS` environment variable): The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `–cluster-schema-registry-creds ` (or `SCHEMA_REGISTRY_CREDS` environment variable) (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

🤖 For [Fully Managed connectors](/content?id=%f0%9f%a4%96-fully-managed-connectors), as examples are [dependent of cloud providers](https://docs.confluent.io/cloud/current/connectors/index.html#cloud-platforms-support), you have the possibility to define specific existing clusters per cloud provider:

* AWS:

```bash
AWS_CLUSTER_NAME
AWS_CLUSTER_REGION
AWS_CLUSTER_CLOUD
AWS_CLUSTER_CREDS
```

* GCP:

```bash
GCP_CLUSTER_NAME
GCP_CLUSTER_REGION
GCP_CLUSTER_CLOUD
GCP_CLUSTER_CREDS
```

* AZURE:

```bash
AZURE_CLUSTER_NAME
AZURE_CLUSTER_REGION
AZURE_CLUSTER_CLOUD
AZURE_CLUSTER_CREDS
```

For example, if you're running an AZURE Fully Managed connector example and `AZURE_CLUSTER_NAME` is set, then this cluster will be used even if you have `CLUSTER_NAME` set.

## 🪄 Specify versions

[playground run](/playground%20run) command allows you to do that very easily !

![specify versions](./images/versions.jpg)

### 🎯 For Confluent Platform (CP)

By default, latest Confluent Platform version is used.

TIP
You can also change cp version while running an example using [playground update-version](/playground%20update-version)

### 🔗 For Connectors

By default, for each connector, the latest available version on [Confluent Hub](https://www.confluent.io/hub/) is used. 

The only 2 exceptions are:

* replicator which is using same version as CP (but you can force a version using `REPLICATOR_TAG` environment variable)
* JDBC which is using same version as CP (but only for CP version lower than 6.x)

Each latest version used is specified on the [Connectors list](/content?id=connectors).

The playground has 3 different ways to use different connector version when running a connector example:

1. Specify the connector version (`--connector-tag` using [playground run](https://kafka-docker-playground.io/#/playground%20run) command)

2. Specify a connector ZIP file (`--connector-zip` using [playground run](https://kafka-docker-playground.io/#/playground%20run) command)

3. Specify a connector JAR file (`--connector-jar` using [playground run](https://kafka-docker-playground.io/#/playground%20run) command)

*Example:*

```bash
00:33:47 ℹ️ 🎯 CONNECTOR_JAR is set with /tmp/kafka-connect-http-1.3.1-SNAPSHOT.jar
/usr/share/confluent-hub-components/confluentinc-kafka-connect-http/lib/kafka-connect-http-1.2.4.jar
00:33:48 ℹ️ 👷 Building Docker image confluentinc/cp-server-connect-base:cp-6.2.1-kafka-connect-http-1.2.4-kafka-connect-http-1.3.1-SNAPSHOT.jar
00:33:48 ℹ️ Remplacing kafka-connect-http-1.2.4.jar by kafka-connect-http-1.3.1-SNAPSHOT.jar
```

When jar to replace cannot be found automatically, the user is able to select the one to replace automatically:

```bash
11:02:43 ℹ️ 🎯 CONNECTOR_JAR is set with /tmp/debezium-connector-postgres-1.4.0-SNAPSHOT.jar
ls: cannot access '/usr/share/confluent-hub-components/debezium-debezium-connector-postgresql/lib/debezium-connector-postgresql-1.4.0.jar': No such file or directory
11:02:44 ❗ debezium-debezium-connector-postgresql/lib/debezium-connector-postgresql-1.4.0.jar does not exist, the jar name to replace could not be found automatically
11:02:45 ℹ️ Select the jar to replace:
1) debezium-api-1.4.0.Final.jar
2) debezium-connector-postgres-1.4.0.Final.jar
3) debezium-core-1.4.0.Final.jar
```

WARNING
You can use both `--connector-tag` and `--connector-jar` at same time (along with `--tag`), but `--connector-tag` and `--connector-zip` are mutually exclusive.

NOTE
For more information about the Connect image used, check [here](/how-it-works?id=🔗-connect-image-used).

TIP
You can also change connector(s) version(s) while running an example using [playground update-version](/playground%20update-version)

## 🐳 Overidding Confluent Plaform Docker images and tags

Docker images being used can be overridden by exporting following environment variables:

* zookeeper (`CP_ZOOKEEPER_IMAGE`)
* kafka (`CP_KAFKA_IMAGE`)
* connect (`CP_CONNECT_IMAGE`)
* schema-registry (`CP_SCHEMA_REGISTRY_IMAGE`)
* control-center (`CP_CONTROL_CENTER_IMAGE`)
* ksqlDb (`CP_KSQL_IMAGE`)
* ksqlDB CLI (`CP_KSQL_CLI_IMAGE`)
* rest-proxy (`CP_REST_PROXY_IMAGE`)

Docker images tags being used can be overridden by exporting following environment variables:

* zookeeper (`CP_ZOOKEEPER_TAG`)
* kafka (`CP_KAFKA_TAG`)
* connect (`CP_CONNECT_TAG`) (`--connect-tag` using [playground run](https://kafka-docker-playground.io/#/playground%20run) command)
* schema-registry (`CP_SCHEMA_REGISTRY_TAG`)
* control-center (`CP_CONTROL_CENTER_TAG`)
* ksqlDb (`CP_KSQL_TAG`)
* ksqlDB CLI (`CP_KSQL_CLI_TAG`)
* rest-proxy (`CP_REST_PROXY_TAG`)

## 🛰 Kraft mode

[Kraft](https://docs.confluent.io/platform/current/kafka-metadata/kraft.html) is enabled by default when used with CP 8+, but you can also force it by setting environment variable `ENABLE_KRAFT` (minimum CP version supported is 7.4)

## ⛳ Options

Selecting options is really easy with [playground run](/playground%20run) menu:

![options](./images/options.jpg)

### 🚀 Enabling ksqlDB

By default, [`ksqldb-server`](https://github.com/vdesabou/kafka-docker-playground/blob/7098800a582bfb2629005366b514a923d2fa037f/environment/plaintext/docker-compose.yml#L135-L171) and [`ksqldb-cli`](https://github.com/vdesabou/kafka-docker-playground/blob/7098800a582bfb2629005366b514a923d2fa037f/environment/plaintext/docker-compose.yml#L173-L183) containers are not started for every test.

You can enable this by setting environment variable `ENABLE_KSQLDB=1` in your shell.

### 💠 Enabling Control Center

By default, [`control-center`](https://github.com/vdesabou/kafka-docker-playground/blob/7098800a582bfb2629005366b514a923d2fa037f/environment/plaintext/docker-compose.yml#L185-L221) container is not started for every test.

You can enable this by setting environment variable `ENABLE_CONTROL_CENTER=1` in your shell.

Control Center "Next Gen" (image `confluentinc/cp-enterprise-control-center-next-gen`) is used by default. If you want to use legacy image, you can enable it by setting environment variable `ENABLE_LEGACY_CONTROL_CENTER=1` in your shell.

Control Center is reachable at http://127.0.0.1:9021

### 🐺 Enabling Conduktor Platform

By default, [`Conduktor Platform`](https://www.conduktor.io) container is not started for every test. 

You can enable this by setting environment variable `ENABLE_CONDUKTOR=1` in your shell.

Conduktor is reachable at [http://127.0.0.1:8080/console](http://127.0.0.1:8080/console) (`admin`/`admin`).

### 3️⃣ Enabling multiple brokers

By default, there is only one kafka node enabled. To enable a three node count, select it in menu.

### 🥉 Enabling multiple connect workers

By default, there is only one connect node enabled. To enable a three connect node count, select it in menu.

### 📊 Enabling JMX Grafana

By default, Grafana dashboard using JMX metrics is not started for every test.

You can enable this by setting environment variable `ENABLE_JMX_GRAFANA=1` in your shell.

📊 Grafana is reachable at [http://127.0.0.1:3000](http://127.0.0.1:3000)
🛡️ Prometheus is reachable at [http://127.0.0.1:9090](http://127.0.0.1:9090)
📛 [Pyroscope](https://pyroscope.io/docs/) is reachable at [http://127.0.0.1:4040](http://127.0.0.1:4040)

#### Grafana dashboards

List of provided dashboards:
 - Confluent Platform overview
 - Zookeeper cluster
 - Kafka cluster
 - Kafka topics
 - Kafka quotas
 - Schema Registry cluster
 - Kafka Connect cluster
 - ksqlDB cluster
 - Kafka Clients
 - Kafka lag exporter
 - Cluster Linking
 - Kafka streams RocksDB
 - Oracle CDC source Connector
 - Mongo source and sink Connector
 - Debezium CDC source Connectors


<!-- tabs:start -->

##### **Confluent Platform overview**

![Confluent Platform overview](images/confluent-platform-overview.png)

#### **Zookeeper cluster**

![Zookeeper cluster dashboard](images/zookeeper-cluster.png)

#### **Kafka cluster**

![Kafka cluster dashboard 0](images/kafka-cluster-0.png)
![Kafka cluster dashboard 1](images/kafka-cluster-1.png)

#### **Kafka topics**

![Kafka topics](images/kafka-topics.png)

#### **Kafka quotas**

For Kafka to output quota metrics, at least one quota configuration is necessary.

A quota can be configured using:

```bash
docker exec broker kafka-configs --bootstrap-server broker:9092 --alter --add-config 'producer_byte_rate=10000,consumer_byte_rate=30000,request_percentage=0.2' --entity-type users --entity-name unknown --entity-type clients --entity-name unknown
```

![Kafka quotas](images/kafka-quotas.png)

#### **Schema Registry cluster**

![Schema Registry cluster](images/schema-registry-cluster.png)

#### **Kafka Connect cluster**

![Kafka Connect cluster dashboard 0](images/kafka-connect-cluster-0.png)
![Kafka Connect cluster dashboard 1](images/kafka-connect-cluster-1.png)

#### **ksqlDB cluster**

![ksqlDB cluster dashboard 0](images/ksqldb-cluster-0.png)
![ksqlDB cluster dashboard 1](images/ksqldb-cluster-1.png)

#### **Kafka streams RocksDB**

![kafkastreams-rocksdb 0](images/kafkastreams-rocksdb.png)

#### **Kafka Clients**

![Kafka Producer](images/kafka-producer.png)

![Kafka Consumer](images/kafka-consumer.png)

#### **Oracle CDC source Connector**

![oraclecdc](images/oraclecdc.jpg)

#### **Debezium CDC source Connectors**

![debezium](images/debezium.png)

#### **Mongo source and sink Connector**

![mongo](images/mongo.png)

<!-- tabs:end -->


### 🐈‍⬛ Enabling kcat

By default, [edenhill/kcat](https://github.com/edenhill/kcat) is not started for every test. 

You can enable this by setting environment variable `ENABLE_KCAT=1` in your shell.

Then you can use it with:

```bash
docker exec kcat kcat -b broker:9092 -L
```

### 🐿️ Enabling Flink

By default, Flink task/jobmanager is not started for every test. 

You can enable Flink for any connector using plaintext deployment by setting environment variable `ENABLE_FLINK=1` in your shell. 

Once enabled, the CLI will ask if you need to download any connectors. Based on the response, you can download one or more connectors from Flinks [maven](https://repo.maven.apache.org/maven2/org/apache/flink/) repository. 

Additonally, you can start Flink in any of the available [deployment modes](https://nightlies.apache.org/flink/flink-docs-master/docs/deployment/overview/#deployment-modes) by navigating to the respective directory:

- `kafka-docker-playground/`
  - `flink/`
    - `flink_app_mode/start.sh`
    - `flink_session_mode/start.sh`
    - `flink_session_sql_mode/start.sh`


🐿️ Flink UI is reacheable using [http://127.0.0.1:8081](http://127.0.0.1:8081) within the flink child directory. If you enable Flink by starting connector deployment, [http://127.0.0.1:18081](http://127.0.0.1:18081) will be used. 

## 🔢 JMX Metrics

JMX metrics are available locally on those ports:

* zookeeper: `9999`
* broker: `10000`
* schema-registry: `10001`
* connect: `10002`

In order to easily gather JMX metrics, you can execute [🧠 CLI](/cli) with `get-jmx-metrics` command:

```bash
$ playground get-jmx-metrics

  Get JMX metrics from a component.
  
  Check documentation /how-to-use?id=%f0%9f%94%a2-jmx-metrics

Usage:
  playground get-jmx-metrics [OPTIONS]
  playground get-jmx-metrics --help | -h

Options:
  --component, -c COMPONENT
    Component name.
    Allowed: zookeeper, broker, connect, schema-registry
    Default: connect

  --domain, -d DOMAIN
    Domain name.

  --help, -h
    Show this help

Examples:
  playground get-jmx-metrics --component connect
  playground get-jmx-metrics --component connect --domain "kafka.connect
  kafka.consumer kafka.producer"
  playground get-jmx-metrics -c broker
```

Example (without specifying domain):

```bash
$ playground get-jmx-metrics -c connect
17:35:35 ❗ You did not specify a list of domains, all domains will be exported!
17:35:35 ℹ️ This is the list of domains for component connect
JMImplementation
com.sun.management
java.lang
java.nio
java.util.logging
jdk.management.jfr
kafka.admin.client
kafka.connect
kafka.consumer
kafka.producer
17:35:38 ℹ️ JMX metrics are available in /tmp/jmx_metrics.log file
```

Example (specifying domain):

```bash
$ playground get-jmx-metrics -c connect -d "kafka.connect kafka.consumer kafka.producer"
17:38:00 ℹ️ JMX metrics are available in /tmp/jmx_metrics.log file
```

WARNING
Local install of Java `JDK` (at least 1.8) is required to run `playground get-jmx-metrics`

## 📝 See properties file

Because the playground use **[Docker override](/how-it-works?id=🐳-docker-override)**, not all configuration parameters are in same `docker-compose.yml` file.

In order to easily see the end result properties file, you can use execute [playground container get-properties](/playground%20container%20get-properties) command

*Example:*

```bash
$ playground get-properties -c connect
bootstrap.servers=broker:9092
config.providers.file.class=org.apache.kafka.common.config.provider.FileConfigProvider
config.providers=file
config.storage.replication.factor=1
config.storage.topic=connect-configs
connector.client.config.override.policy=All
consumer.confluent.monitoring.interceptor.bootstrap.servers=broker:9092
consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor
group.id=connect-cluster
internal.key.converter.schemas.enable=false
internal.key.converter=org.apache.kafka.connect.json.JsonConverter
internal.value.converter.schemas.enable=false
internal.value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter=org.apache.kafka.connect.storage.StringConverter
log4j.appender.stdout.layout.conversionpattern=[%d] %p %X{connector.context}%m (%c:%L)%n
log4j.loggers=org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR
offset.storage.replication.factor=1
offset.storage.topic=connect-offsets
plugin.path=/usr/share/confluent-hub-components/confluentinc-kafka-connect-http
producer.client.id=connect-worker-producer
producer.confluent.monitoring.interceptor.bootstrap.servers=broker:9092
producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
rest.advertised.host.name=connect
rest.port=8083
status.storage.replication.factor=1
status.storage.topic=connect-status
topic.creation.enable=true
value.converter.schema.registry.url=http://schema-registry:8081
value.converter.schemas.enable=false
value.converter=io.confluent.connect.avro.AvroConverter
```

## ♻️ Re-create containers

Because the playground uses **[Docker override](/how-it-works?id=🐳-docker-override)**, not all configuration parameters are in same `docker-compose.yml` file and also `docker-compose` files in the playground depends on environment variables to be set.

For these reasons, if you want to make a change in one of the `docker-compose` files (without restarting the example from scratch), it is not simply a matter of doing `docker-compose up -d` 😅!

However, when you execute an example, you get in the output the [playground container recreate](/playground%20container%20recreate) in order to easily re-create modified container(s) 🥳.

*Example:*

```bash
12:02:18 ℹ️ ✨If you modify a docker-compose file and want to re-create the container(s),
 run cli command playground container recreate
```

So you can modify one of the `docker-compose` files (in that case either [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml) or [`connect/connect-http-sink/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/docker-compose.plaintext.yml)), and then run execute [🧠 CLI](/cli) with `playground container recreate` command:

*Example:*

After editing [`connect/connect-http-sink/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/docker-compose.plaintext.yml) and updated both `connect` and `http-service-no-auth`, the suggested cli command was ran:

```bash
$ playground container recreate
http-service-ssl-basic-auth is up-to-date
http-service-oauth2-auth is up-to-date
Recreating http-service-no-auth ... 
zookeeper is up-to-date
http-service-no-auth-500 is up-to-date
http-service-mtls-auth is up-to-date
http-service-basic-auth-204 is up-to-date
http-service-basic-auth is up-to-date
broker is up-to-date
Recreating http-service-no-auth ... done
Recreating connect              ... done
control-center is up-to-date
```


# 🎓️ How it works

Before learning how to create your own examples/reproduction models, here are some explanations on how the playground works internally...


## 🐳 Docker override

The playground makes extensive use of docker-compose [override](https://docs.docker.com/compose/extends/) (i.e `docker-compose -f docker-compose1.yml -f docker-compose2.yml ...`).

Each test is built based on an [environment](#/content?id=%F0%9F%94%90-environments), [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext) being the most common one.

TIP
Check **[📝 See properties file](/how-to-use?id=📝-see-properties-file)** section, in order to see the end result properties file.

Let's have a look at some examples to understand how it works:

### 🔓 Connector using PLAINTEXT

Example with ([active-mq-sink.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-active-mq-sink/active-mq-sink.sh)):

At the beginning of the script, we have:

```shell
$ PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
$ playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"
```

The *local* [`${PWD}/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-active-mq-sink/docker-compose.plaintext.yml) file is only composed of:

```yml
---
version: '3.5'
services:
  activemq:
    image: rmohr/activemq:5.15.9
    hostname: activemq
    container_name: activemq
    ports:
      - '61616:61616'
      - '8161:8161'

  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-activemq-sink
```

It contains:

* `activemq` which is a container required for the test.
* `connect` container, which overrides value `CONNECT_PLUGIN_PATH` from [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)

PLAINTEXT environment is used thanks to the call to [playground start-environment](/playground%20start-environment), which invokes the docker-compose command in the end like this:

```bash
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ${PWD}/docker-compose.plaintext.yml up -d
```

### 🔐 Environment SASL/SSL 

Environments are also overriding [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext), so for example [SASL/SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-ssl) has a [docker-compose.yml](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/sasl-ssl/docker-compose.yml) file like this:

```yml
  ####
  #
  # This file overrides values from environment/plaintext/docker-compose.yml
  #
  ####

  zookeeper:
    environment:
      KAFKA_OPTS: -Djava.security.auth.login.config=/etc/kafka/secrets/zookeeper_jaas.conf
                  -Dzookeeper.authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider
                  -DrequireClientAuthScheme=sasl
                  -Dzookeeper.allowSaslFailedClients=false
    volumes:
      - ../../environment/sasl-ssl/security:/etc/kafka/secrets

  broker:
    volumes:
      - ../../environment/sasl-ssl/security:/etc/kafka/secrets
    environment:
      KAFKA_INTER_BROKER_LISTENER_NAME: SASL_SSL
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: SASL_SSL:SASL_SSL
      KAFKA_ADVERTISED_LISTENERS: SASL_SSL://broker:9092
      KAFKA_LISTENERS: SASL_SSL://:9092
      CONFLUENT_METRICS_REPORTER_SECURITY_PROTOCOL: SASL_SSL
      CONFLUENT_METRICS_REPORTER_SASL_JAAS_CONFIG: "org.apache.kafka.common.security.plain.PlainLoginModule required \
        username=\"client\" \
        password=\"client-secret\";"
      CONFLUENT_METRICS_REPORTER_SASL_MECHANISM: PLAIN
      CONFLUENT_METRICS_REPORTER_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.client.truststore.jks
      CONFLUENT_METRICS_REPORTER_SSL_TRUSTSTORE_PASSWORD: confluent
      CONFLUENT_METRICS_REPORTER_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.client.keystore.jks
      CONFLUENT_METRICS_REPORTER_SSL_KEYSTORE_PASSWORD: confluent
      CONFLUENT_METRICS_REPORTER_SSL_KEY_PASSWORD: confluent
      KAFKA_SASL_ENABLED_MECHANISMS: PLAIN
      KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL: PLAIN
      KAFKA_SSL_KEYSTORE_FILENAME: kafka.broker.keystore.jks
      KAFKA_SSL_KEYSTORE_CREDENTIALS: broker_keystore_creds
      KAFKA_SSL_KEY_CREDENTIALS: broker_sslkey_creds
      KAFKA_SSL_TRUSTSTORE_FILENAME: kafka.broker.truststore.jks
      KAFKA_SSL_TRUSTSTORE_CREDENTIALS: broker_truststore_creds
      # enables 2-way authentication
      KAFKA_SSL_CLIENT_AUTH: "required"
      KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM: "HTTPS"
      KAFKA_OPTS: -Djava.security.auth.login.config=/etc/kafka/secrets/broker_jaas.conf
      KAFKA_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=TEST.*$$/$$1/,DEFAULT

      <snip>
```

As you can see, it only contains what is required to add SASL/SSL to a PLAINTEXT environment 💫 !

### 🔏 Connector using non-plaintext environment

Any connector example can be ran with any environment using `environment` option of [playground run](/playground%20run?id=environment-environment) command.

## 🔗 Connect image used

The Kafka Connect image is either based on [`cp-server-connect-base`](https://hub.docker.com/r/confluentinc/cp-server-connect-base) for version greater than `5.3.0` or [`cp-kafka-connect-base`](https://hub.docker.com/r/confluentinc/cp-kafka-connect-base) otherwise.

Several tools are [installed](https://github.com/vdesabou/kafka-docker-playground/blob/5b7a6842e7d9e87242ca0b5948e1a70a7b4b80ce/scripts/utils.sh#L4) automatically on the image such as `openssl`, `tcpdump`, `iptables`, `netcat`, etc..

If you're missing a tool, you can install it at runtime, some examples:

```bash
# directly with rpm
docker exec -i --user root connect bash -c "curl http://mirror.centos.org/centos/7/os/x86_64/Packages/tree-1.6.0-10.el7.x86_64.rpm -o tree-1.6.0-10.el7.x86_64.rpm && rpm -Uvh tree-1.6.0-10.el7.x86_64.rpm"
# using yum
docker exec -i --user root connect bash -c "yum update -y --disablerepo='Confluent*' && yum install findutils -y"
```

## ↔️ Default Connect converter used

All connect example are using the converters defined in Connect Worker properties defined [here](https://github.com/vdesabou/kafka-docker-playground/blob/95f6e1d34d0261c5de76088d88fc6930f8053fd4/environment/plaintext/docker-compose.yml#L197-L199):

```yml
CONNECT_KEY_CONVERTER: "org.apache.kafka.connect.storage.StringConverter"
CONNECT_VALUE_CONVERTER: "io.confluent.connect.avro.AvroConverter"
CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
```

Therefore:

* String converter for key
* Avro converter for value

This can, of course, be overridden at connector level.



# 👷‍♂️ How to build your own examples or reproduction models with reusables

Below is a collection of *how to* that you can re-use when you build your own examples or reproduction models.

## 🛠 Bootstrap reproduction model

Execute [🧠 CLI](/cli) with `playground repro bootstrap` [command](/playground%20repro%20bootstrap). It will start in interactive mode.

Examples:

### Basic

<script async id="asciicast-646555" src="https://asciinema.org/a/646555.js"></script>

### Deprecated: Java producer (`--producer`)

WARNING
Most of times, it's much simpler to use `playground topic produce` [CLI](/playground%20topic%20produce)

Use java producer only if you have very specific requirements such as specifying record timestamp
See [here](/legacy-java-producer) for instructions


### With custom SMT (`--custom-smt`)

If you want to add a custom SMT, just add `--custom-smt` flag.

This will create the following files:

![file structure](./images/custom_smt.jpg)

This is a no-op custom SMT:

```java
    @Override
    public R apply(R record) {
        log.info("Applying no-op MyCustomSMT");
        // add your logic here
        return record.newRecord(
            record.topic(),
            record.kafkaPartition(),
            record.keySchema(),
            record.key(),
            record.valueSchema(),
            record.value(),
            record.timestamp()
        );
    }
```

It will also add the required steps to compile code:

```bash
for component in MyCustomSMT-000000
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done
```

It will copy the jar to the connector lib folder:

```bash
log "📂 Copying custom jar to connector folder /usr/share/confluent-hub-components/debezium-debezium-connector-sqlserver/lib/"
docker cp /home/vsaboulin/kafka-docker-playground/scripts/cli/../../reproduction-models/connect-connect-debezium-sqlserver-source/MyCustomSMT-000000/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar connect:/usr/share/confluent-hub-components/debezium-debezium-connector-sqlserver/lib/
log "📂 Copying custom jar to connector folder /usr/share/confluent-hub-components/confluentinc-connect-transforms/lib/"
docker cp /home/vsaboulin/kafka-docker-playground/scripts/cli/../../reproduction-models/connect-connect-debezium-sqlserver-source/MyCustomSMT-000000/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar connect:/usr/share/confluent-hub-components/confluentinc-connect-transforms/lib/
log "♻️ Restart connect worker to load"
docker restart connect
sleep 45
```

And add the transform config to connector:

```json
  "transforms": "MyCustomSMT",
  "transforms.MyCustomSMT.type": "com.github.vdesabou.kafka.connect.transforms.MyCustomSMT",
```

### With pipeline (`--pipeline`)

All the steps to create a pipeline, i.e an example with source and sink connectors are automated:

Example:

<script async id="asciicast-646556" src="https://asciinema.org/a/646556.js"></script>

It will automatically:

* Add sink example(s) (you can select multiple !) at the end of source example
* Modify sink converters (key and value) to use same as source example
* Use same kafka topic for all connectors
* Add all required containers for all sink and source
* Update `CONNECT_PLUGIN_PATH` to include all connectors

## 👉 Producing data

### 🧠 playground topic produce

Just use `playground topic produce` [CLI](/playground%20topic%20produce), it's magic !

It you prefer to use legacy way, see below:

### Deprecated ♨️ Java producers

WARNING
Most of times, it's much simpler to use `playground topic produce` [CLI](/playground%20topic%20produce)

Use java producer only if you have very specific requirements such as specifying record timestamp
See [here](/legacy-java-producer) for instructions

### 🔤 kafka-console-producer

<!-- tabs:start -->

#### **seq**

```bash
seq -f "This is a message %g" 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic
```

#### **Heredoc**

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic << EOF
This is my message 1
This is my message 2
EOF
```

#### **Heredoc JSON**

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **Key**

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
key1,value1
key1,value2
key2,value1
EOF
```

#### **Key and JSON**

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
key1,{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
key2,{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
key3,{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **JSON with schema (and key)**

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
1,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record1"}}
2,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record2"}}
3,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record3"}}
EOF
```

<!-- tabs:end -->

### 🔣 kafka-avro-console-producer

<!-- tabs:start -->

#### **seq**

```
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

#### **Heredoc**

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **Key**

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
{"ID": 222}|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF
```

#### **String Key**

If the key needs to be a string, you can use `key.serializer` to specify it:

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
111|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
222|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF
```


TIP
If AVRO schema is very complex, it is better to use [♨️ Java producer](/reusables?id=♨%EF%B8%8F-java-producers) above.

<!-- tabs:end -->

### 🔣 kafka-protobuf-console-producer

<!-- tabs:start -->

#### **seq**

```
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-protobuf-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic-proto --property value.schema='syntax = "proto3"; message MyRecord { string f1 = 1; }'
```

#### **Heredoc**

```bash
docker exec -i connect kafka-protobuf-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='syntax = "proto3"; message MyRecord { string f1 = 1; }' << EOF
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
EOF
```

#### **Key**

```bash
docker exec -i connect kafka-protobuf-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property key.schema='syntax = "proto3"; message MyRecord { string ID = 1; }' --property value.schema='syntax = "proto3"; message MyRecord { string f1 = 1; }'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"f1":"value1"}
{"ID": 222}|{"f1":"value2"}
{"ID": 333}|{"f1":"value3"}
EOF
```

<!-- tabs:end -->

TIP
If Protobuf schema is very complex, it is better to use [♨️ Java producer](/reusables?id=♨%EF%B8%8F-java-producers) above.


### 🔣 kafka-json-schema-console-producer

<!-- tabs:start -->

#### **seq**

```
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"object","properties":{"f1":{"type":"string"}}}'
```

#### **Heredoc**

```bash
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"object","properties":{"f1":{"type":"string"}}}' << EOF
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
EOF
```

#### **Key**

```bash
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property key.schema='{"additionalProperties":false,"title":"ID","description":"ID description","type":"object","properties":{"ID":{"description":"ID","type":"integer"}},"required":["ID"]}' --property value.schema='{"type":"object","properties":{"f1":{"type":"string"}}}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"f1": "value1"}
{"ID": 222}|{"f1": "value2"}
EOF
```

<!-- tabs:end -->

TIP
If JSON Schema schema is very complex, it is better to use [♨️ Java producer](/reusables?id=♨%EF%B8%8F-java-producers) above.

### 🌪 kafka-producer-perf-test

```bash
docker exec broker kafka-producer-perf-test --topic a-topic --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker:9092
```

## 👉 Consuming data

### 🧠 playground topic consume

Just use `playground topic consume` [CLI](/playground%20topic%20consume), it's magic !

It you prefer to use legacy way, see below:

### 🔤 [kafka-console-consumer](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/kafka-commands.html#consume-records)

<!-- tabs:start -->

#### **Simplest**

```
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic --from-beginning --max-messages 1
```

#### **Display Key**

```bash
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1
```


<!-- tabs:end -->


TIP
Using `timeout` command prevents the command to run forever.
It is [ignored](https://github.com/vdesabou/kafka-docker-playground/blob/c65704df7b66a2c47321d04fb75f43a8bbb4fef1/scripts/utils.sh#L650-L658) if not present on your machine.


### 🔣 [kafka-avro-console-consumer](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/kafka-commands.html#consume-avro-records)

<!-- tabs:start -->

#### **Simplest**

```
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1
```

#### **Display Key**

```
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1
```

#### **String Key**

If the key is a string, you can use `key.deserializer` to specify it:

```bash
docker exec connect kafka-avro-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --from-beginning --max-messages 1
```

<!-- tabs:end -->
### 🔣 kafka-protobuf-console-consumer

<!-- tabs:start -->

#### **Simplest**

```
docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1
```

#### **Display Key**

```
docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1
```

<!-- tabs:end -->



### 🔣 kafka-json-schema-console-consumer


<!-- tabs:start -->

#### **Simplest**

```
docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1
```

#### **Display Key**

```
docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1
```

<!-- tabs:end -->

## 🧙 How to install other connectors

To run an example with additional connector (or SMT that you can get from Confluent Hub), simply add it to the list of `CONNECT_PLUGIN_PATH`:

Example with S3 source and S3 sink:

```yml
services:
  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-s3-source,/usr/share/confluent-hub-components/confluentinc-kafka-connect-s3
```

Example with [confluentinc/connect-transforms](https://www.confluent.io/hub/confluentinc/connect-transforms) SMT:

```yml
services:
  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-s3-source,/usr/share/confluent-hub-components/confluentinc-connect-transforms
```

TIP
You can also specify versions when specifying multiple connector/SMT, see [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%94%97-for-connectors).


## 🐛 Debugging tools

### ✨ Remote debugging

Java Remote debugging is the perfect tool for troubleshooting Kafka connectors for example.

TIP
Following are instructions for [Visual Studio Code ](https://code.visualstudio.com/docs/java/java-debugging), but it is exactly the same principle for [IntelliJ IDEA](https://www.jetbrains.com/help/idea/tutorial-remote-debug.html#436b3b68).

#### ☑️ Prerequisites

Make sure you have already the required Visual Studio code extensions by following [this](https://code.visualstudio.com/docs/java/java-debugging#_install).

#### 💫 Full example

Here is a full example using [HDFS 2 sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs2-sink) connector and [Visual Studio Code ](https://code.visualstudio.com/docs/java/java-debugging):

1. Launch the example as usual, i.e start `./hdfs2-sink.sh`.

2. Clone and open [`confluentinc/kafka-connect-hdfs`](https://github.com/confluentinc/kafka-connect-hdfs) repository in Visual Studio Code.

3. Switch to the branch corresponding to the connector version you're going to run. 
 
In my example, the connector version is `10.1.1`, so I'm switching to branch tag `v10.1.1`:

![remote_debugging](./images/remote_debugging2.jpg)

4. Execute [🧠 CLI](/cli) with `enable-remote-debugging` command:

```bash
$ playground debug enable-remote-debugging -c connect
namenode is up-to-date
zookeeper is up-to-date
hive-metastore-postgresql is up-to-date
datanode is up-to-date
presto-coordinator is up-to-date
hive-server is up-to-date
hive-metastore is up-to-date
broker is up-to-date
schema-registry is up-to-date
Recreating connect ... done
control-center is up-to-date
15:34:36 ℹ️ If you use Visual Studio Code:
15:34:36 ℹ️ Edit .vscode/launch.json with
15:34:36 ℹ️ 
{
    "version": "0.2.0",
    "configurations": [
    
        {
            "type": "java",
            "name": "Debug connect container",
            "request": "attach",
            "hostName": "127.0.0.1",
            "port": 5005,
            "timeout": 30000
        }
    ]
}

15:34:36 ℹ️ See https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging
```
   
5. [Configure](https://code.visualstudio.com/docs/java/java-debugging#_configure) remote debugging by clicking on menu `Run`->`Add Configuration...`:

![remote_debugging](./images/remote_debugging1.jpg)

Then copy/paste the following entry:

```json
{
    "type": "java",
    "name": "Debug connect container",
    "request": "attach",
    "hostName": "127.0.0.1",
    "port": 5005,
    "timeout": 30000
}
```

Note: you can also directly edit file `.vscode/launch.json`:

```json
{
    "version": "0.2.0",
    "configurations": [
    
        {
            "type": "java",
            "name": "Debug connect container",
            "request": "attach",
            "hostName": "127.0.0.1",
            "port": 5005,
            "timeout": 30000
        }
    ]
}
```

*Example:*

![remote_debugging](./images/remote_debugging3.jpg)

5. Go in `Run and Debug` and make sure to select the `Debug Connect container` config:

![remote_debugging](./images/remote_debugging5.jpg)

7. Click on the green play button

![remote_debugging](./images/remote_debugging6.jpg)

8. Add breakpoint(s) where you want, for example [here](https://github.com/confluentinc/kafka-connect-hdfs/blob/9a5e68d7294a79c40050efd7b51d7428c7f7c4d5/src/main/java/io/confluent/connect/hdfs/TopicPartitionWriter.java#L894):

![remote_debugging](./images/remote_debugging4.jpg)

9. Process some messages:

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

10. See results 🍿:

![remote_debugging](./images/remote_debugging7.jpg)

![remote_debugging](https://github.com/vdesabou/gifs/raw/master/docs/images/remote_debugging.gif)


Note (*for Confluent employees because control center code is proprietary*): for `control-center`, you can use following override (note the `5006` port in order to avoid clash with `connect` port):

```yml
  control-center:
    ports:
      - "9021:9021"
      - "5006:5006"
    environment:
      CONTROL_CENTER_OPTS: "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5006"
```

### 🔗 Connectors

In order to enable `TRACE`(or `DEBUG`) logs for connectors, use the `admin/loggers` endpoint (see docs [here](https://docs.confluent.io/platform/current/connect/logging.html#change-the-log-level-for-a-specific-logger)):

*Example:*

```bash
curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.oracle.cdc \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'
```

WARNING
Make sure to update `io.confluent.connect.oracle.cdc` above with the package you want to troubleshoot.

Useful packages:

* `io.confluent.kafka.schemaregistry.client.rest.RestService`: to track schema registry requests
* `org.apache.kafka.connect.runtime.TransformationChain`: to see records before, during and after SMT

Or just use [CLI](/playground%20connector%20log-level) `playground connector log-level` 

Example:

```bash
playground connector log-level --level TRACE
```

### 🔑 SSL debug

Add `-Djavax.net.debug=all` in your `docker-compose` file:

*Example:*

```yml
  connect:
    KAFKA_OPTS: -Djavax.net.debug=all (or -Djavax.net.debug=ssl:handshake)
```

Or just use [CLI](/playground%20debug%20java-debug) `playground debug java-debug` with `--type ssl_all` or `--type ssl_handshake`.

### 🔒 Kerberos debug

Add `-Dsun.security.krb5.debug=true` in your `docker-compose` file:

*Example:*

```yml
  connect:
    KAFKA_OPTS: -Dsun.security.krb5.debug=true
```

Or just use [CLI](/playground%20debug%20java-debug) `playground debug java-debug` with `--type kerberos`.

### 🔬 Class loading

Add `-verbose:class` in your `docker-compose` file to troubleshoot a `ClassNotFoundException` for example:

*Example:*

```yml
  connect:
    environment:
      KAFKA_OPTS: -verbose:class
```

Or just use [CLI](/playground%20debug%20java-debug) `playground debug java-debug` with `--type class_loading`.

In logs, you'll see:

```log
[Loaded org.apache.kafka.connect.runtime.isolation.DelegatingClassLoader$$Lambda$20/1007251739 from org.apache.kafka.connect.runtime.isolation.DelegatingClassLoader]
[Loaded java.lang.invoke.LambdaForm$MH/1556595366 from java.lang.invoke.LambdaForm]
[Loaded org.reflections.util.ConfigurationBuilder from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.serializers.Serializer from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.adapters.MetadataAdapter from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.Scanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.AbstractScanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.TypeAnnotationsScanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.AbstractScanner$$Lambda$21/1725097945 from org.reflections.scanners.AbstractScanner]
[Loaded org.reflections.scanners.SubTypesScanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.util.FilterBuilder from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.util.FilterBuilder$Matcher from file:/usr/share/java/kafka/reflections-0.9.12.jar]
```

### 🕸️ Debug ServiceNow or Salesforce

Those connectors use low level [com.google.api.client.http](https://developers.google.com/api-client-library/java) library.

In order to activate debug logs to see requests/responses, you can just add the `volumes` mount with existing `../../connect/connect-servicenow-source/nginx-proxy/logging.properties` file and add `KAFKA_OPTS: -Djava.util.logging.config.file=/tmp/logging.properties`:

Example:

```yml
  connect:
    volumes:
      - ../../connect/connect-servicenow-source/nginx-proxy/logging.properties:/tmp/logging.properties
    environment:
      KAFKA_OPTS: -Djava.util.logging.config.file=/tmp/logging.properties
```

This is how the `logging.properties` looks like:

```bash
$ cat /tmp/logging.properties
handlers=java.util.logging.ConsoleHandler
java.util.logging.ConsoleHandler.level=ALL
com.google.api.client.http.level=ALL
```

### 🌍 Debug HTTP sink

This connector use low level [Apache HTTP client](https://hc.apache.org/httpcomponents-client-5.2.x/) library.

In order to activate debug logs to see requests/responses, you can use `jcl-over-slf4j-2.0.7.jar` (wget https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar):

Example:

```yml
  connect:
    volumes:
      - ../../connect/connect-http-sink/jcl-over-slf4j-2.0.7.jar:/usr/share/confluent-hub-components/confluentinc-kafka-connect-http/lib/jcl-over-slf4j-2.0.7.jar
```

NOTE
It is already set in all HTTP sink examples.

Then you can enable TRACE logs on `org.apache.http`:

```bash
$ playground debug log-level set --package "org.apache.http" --level TRACE
```

or legacy way:

```bash
curl --request PUT \
  --url http://localhost:8083/admin/loggers/org.apache.http \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'
```

### 🕵️‍♂️ See TLS traffic with mitmproxy

[mitmproxy](https://github.com/mitmproxy/mitmproxy) 

1. Add `mitmproxy` container in your `docker-compose` file:

```yml
  mitmproxy:
    image: mitmproxy/mitmproxy
    hostname: mitmproxy
    container_name: mitmproxy
    command: mitmdump --flow-detail 4
    ports:
      - "8080:8080"
    volumes:
      - $HOME/.mitmproxy:/home/mitmproxy/.mitmproxy
```

2. Add in your script after all containers are started:

```bash
cat $HOME/.mitmproxy/mitmproxy-ca-cert.pem | docker exec -i --privileged --user root connect bash -c "cat >/etc/ssl/certs/ca-bundle.crt"
cat $HOME/.mitmproxy/mitmproxy-ca-cert.pem | docker exec -i --privileged --user root connect bash -c "keytool -importcert --cacerts -storepass changeit -noprompt"
```

3. Use mitmproxy proxy in your connector config:

Example:

```json
"proxy.url": "mitmproxy:8080"
```

4. Check TLS traffic in clear text by checking logs of `mitmproxy` container

```bash
playgroundd container  logs -c mitmproxy

or

playground container logs --open --container mitmproxy
```

### 🕵 TCP Dump

It is sometime necessary to sniff the network in order to better understand what's going on.

Just use [CLI](/cli?id=%f0%9f%8e%af-thread-dump) `playground debug tcp-dump`.

```bash
playground debug tcp-dump --help
playground debug tcp-dump - 🕵️‍♂️ Take a tcp dump (sniffing network)

== Usage ==
  playground debug tcp-dump [OPTIONS]
  playground debug tcp-dump --help | -h

== Options ==
  --container, -c CONTAINER
    🐳 Container name
    Default: connect

  --port PORT
    Port on which tcp dump should be done, if not set sniffing is done on every
    port

  --duration DURATION
    Duration of the dump (default is 30 seconds).
    Default: 30

  --help, -h
    Show this help

Examples
  playground debug tcp-dump --container control-center --port 9021 --duration 60
```

### 👻 Heap Dump

It is sometime necessary to get a [heap dump](https://www.baeldung.com/java-heap-dump-capture).

Just use [CLI](/cli?id=%f0%9f%8e%af-thread-dump) `playground debug heap-dump`.

```bash
$ playground debug heap-dump --help  
playground debug heap-dump

  👻 Take a heap dump
  
  🔖 It will save output to a .hprof file. VisualVM (https://visualvm.github.io/)
  or MAT (https://www.eclipse.org/mat/) can be used to read the file.

== Usage ==
  playground debug heap-dump [OPTIONS]
  playground debug heap-dump --help | -h

== Options ==
  --container, -c CONTAINER
    🐳 Container name
    Default: connect

  --help, -h
    Show this help

Examples
  playground debug heap-dump
  playground debug heap-dump --container broker
```

You can also set `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp` to generate heap dump automatically when hitting OOM:

Example:

```yml
  connect:
    environment:
      KAFKA_OPTS: -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp
      KAFKA_HEAP_OPTS: " -Xms2G -Xmx4G"
```

### 🎯 Thread Dump

It is sometime necessary to get a [Java thread dump](https://www.baeldung.com/java-thread-dump).

Just use [CLI](/cli?id=%f0%9f%8e%af-thread-dump) `playground debug thread-dump`.

```bash
$ playground debug thread-dump --help
playground debug thread-dump

  🎯 Take a java thread dump
  
  🔖 It will save output to a file and open with text editor set with config.ini
  (default is code)

== Usage ==
  playground debug thread-dump [OPTIONS]
  playground debug thread-dump --help | -h

== Options ==
  --container, -c CONTAINER
    🐳 Container name
    Default: connect

  --help, -h
    Show this help

Examples
  playground debug thread-dump
  playground debug thread-dump --container broker
```
You can use [Thread Dump Analyzer](http://the-babel-tower.github.io/tda.html) for example to analyze results.

### 🛩️ Flight Recorder

It is sometime necessary to monitor with [Flight Recorder](https://www.baeldung.com/java-flight-recorder-monitoring).

Just use [CLI](/cli?id=%f0%9f%8e%af-thread-dump) `playground debug flight-recorder`.

```bash
$ playground debug flight-recorder --help 
playground debug flight-recorder

  🛩️ Record flight recorder
  
  Read more about it at https://www.baeldung.com/java-flight-recorder-monitoring
  
  Open the jfr file with JDK Mission Control JMC(https://jdk.java.net/jmc/)

== Usage ==
  playground debug flight-recorder [OPTIONS]
  playground debug flight-recorder --help | -h

== Options ==
  --container, -c CONTAINER
    🐳 Container name
    Default: connect

  --action ACTION (required)
    🟢 start or stop
    Allowed: start, stop

  --help, -h
    Show this help

Examples
  playground debug flight-recorder --action start
  playground debug flight-recorder --action stop
```

## 🚫 Blocking traffic

It is sometime necessary for a reproduction model to simulate network issues like blocking incoming or outgoing traffic.

Just use [CLI](/cli?id=%f0%9f%8e%af-thread-dump) `playground debug block-traffic`.

```bash
$ playground debug block-traffic --help
playground debug block-traffic - 🚫 Blocking traffic using iptables

== Usage ==
  playground debug block-traffic [OPTIONS]
  playground debug block-traffic --help | -h

== Options ==
  --container, -c CONTAINER
    🐳 Container name
    Default: connect

  --destination DESTINATION (required)
    Destination: it could be an ip address, a container name or a hostname

  --port PORT
    Port on which tcp traffic should be blocked

  --action ACTION (required)
    🟢 start or stop
    Allowed: start, stop

  --help, -h
    Show this help

Examples
  playground debug block-traffic --destination google.com --action start
  playground debug block-traffic --container broker --destination zookeeper
  --action start
```

<!-- ## 🐌 Add latency

It is sometime necessary for a reproduction model to simulate latency between components.

The [connect image](/how-it-works?id=🔗-connect-image-used) used by the playground contains [`tc`](https://man7.org/linux/man-pages/man8/tc.8.html) tool, and most importantly contains functions [`add_latency()`](https://github.com/vdesabou/kafka-docker-playground/blob/495578d413ff6b9db1d612ee8b1ebdf695f7ab51/scripts/utils.sh#L1062-L1095), [`get_latency()`](https://github.com/vdesabou/kafka-docker-playground/blob/495578d413ff6b9db1d612ee8b1ebdf695f7ab51/scripts/utils.sh#L1052-L1059)` and `[clear_traffic_control()](https://github.com/vdesabou/kafka-docker-playground/blob/495578d413ff6b9db1d612ee8b1ebdf695f7ab51/scripts/utils.sh#L1039-L1050)`:

TIP
A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-servicenow-source/servicenow-source-repro-read-timeout.sh).

*Example:*

Adding latency from `nginx_proxy` to `connect`:

```bash
add_latency nginx_proxy connect 25000ms

latency_put=$(get_latency nginx_proxy connect)
log "Latency from nginx_proxy to connect AFTER traffic control: $latency_put ms"

log "Clear traffic control"
clear_traffic_control nginx_proxy
```

`connect` image has `tc` installed but if you want to use it with broker for example, you need to install it, for example:

```bash
docker exec --privileged --user root -i broker bash -c 'yum install -y libmnl && wget http://vault.centos.org/8.1.1911/BaseOS/x86_64/os/Packages/iproute-tc-4.18.0-15.el8.x86_64.rpm && rpm -i --nodeps --nosignature http://vault.centos.org/8.1.1911/BaseOS/x86_64/os/Packages/iproute-tc-4.18.0-15.el8.x86_64.rpm'
``` -->

## 🏚 Simulate TCP connections problems

[emicklei/zazkia](https://github.com/emicklei/zazkia) is a nice tool to simulate a TCP connection issues (reset,delay,throttle,corrupt).

Just use [CLI](/playground%20tcp-proxy) `playground tcp-proxy`.

```bash
$ playground tcp-proxy
 🏚 Zazkia TCP Proxy commands

== Usage ==
  playground tcp-proxy COMMAND
  playground tcp-proxy [COMMAND] --help | -h

== Commands ==
  start                             💗 Start the TCP proxy and automatically replace connector config with zazkia hostname and port 49998
  get-connections                   🧲 Get Zazkia active TCP connections config and stats
  delay                             ⏲️ Add milliseconds delay to service response.
  break                             💔 Break sending the response to the client.
  close-connection                  ❌ Close the Zazkia active TCP connections
  close-all-connection-with-error   🧹 Close all Zazkia TCP connections which are in error state (close all with error button in Zazkia UI)
  toggle-accept-connections         🙅‍♂️ Change whether new connections can be accepted
  toggle-reads-client               ✅ Change whether reading data from the client is enabled.
  toggle-reads-service              ✅ Change whether reading data from the service is enabled.
  toggle-writes-client              ✅ Change whether writing data to the client is enabled.
  toggle-writes-service             ✅ Change whether reading data to the service is enabled.
```

## 🌐 Using HTTPS proxy

There are several connector examples which include HTTPS proxy (check for `also with 🌐 proxy` in the **[Content](/content.md)** section).

TIP
A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink-proxy.sh). 

Here are the steps to follow:

1. Copy [`connect/connect-aws-s3-sink/nginx-proxy`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink/nginx-proxy) directory into your test directory.

2. Update [`connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf) with the domain name required for your needs.

*Example:*

```conf
        server_name  service-now.com;
        server_name  *.service-now.com;
```

TIP
If you need a proxy to reach another docker container, as opposed to a domain, use following example, where `schema-registry` is the name of the container:


```
http {
    access_log /var/log/nginx_access.log;
    error_log /var/log/nginx_errors.log;

    upstream docker-schema-registry {
        server schema-registry:8081;
    }

    server {
        listen       8888;
        location / {
            proxy_pass         http://docker-schema-registry;
            proxy_redirect     off;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Host $server_name;
        }
    }
}
```

3. Add this in your `docker-compose` file:

```yml
  nginx-proxy:
    image: reiz/nginx_proxy:latest
    hostname: nginx-proxy
    container_name: nginx-proxy
    ports:
      - "8888:8888"
    volumes:
      - ../../connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf:/usr/local/nginx/conf/nginx.conf
```

WARNING
Make sure to update `../../connect/connect-aws-s3-sink` above with the right path.

4. [Optional] In order to make sure the proxy is used, you can set `dns: 0.0.0.0` in the connect instance, so that there is no internet connectivity.

```yml
  connect:
    <snip>
    environment:
      <snip>
    dns: 0.0.0.0
```

5. In you connector configuration, update the proxy configuration parameter with `https://nginx-proxy:8888`.

*Example:*

```json
"s3.proxy.url": "https://nginx-proxy:8888"
```

NOTE
If your proxy requires HTTP2 support, there is a full example available in this example: [GCP Pub/Sub Source connector](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-pubsub-source/gcp-pubsub-nginx-proxy.sh)

### 🔐 Proxy with BASIC authentication

If you want to setup BASIC authentication, you can use [ubuntu/squid](https://hub.docker.com/r/ubuntu/squid) image.

TIP
Some complete examples are available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink-proxy-basic-auth.sh) and [there](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-salesforce-platform-events-sink/salesforce-platform-events-sink-proxy-basic-auth.sh)

* in your `docker-compose`, add `squid` as below:


```yml
  squid:
    image: ubuntu/squid
    hostname: squid
    container_name: squid
    ports:
      - "8888:8888"
    volumes:
      - ../../connect/connect-aws-s3-sink/squid/passwords:/etc/squid/passwords
      - ../../connect/connect-aws-s3-sink/squid/squid.conf:/etc/squid/squid.conf
```

Proxy details:

* container: squid
* port: 8888
* user: admin
* password: 1234

Example with S3 sink:

```json
  "s3.proxy.url": "https://squid:8888",
  "s3.proxy.user": "admin",
  "s3.proxy.password": "1234",
```

Example with Salesforce:

```json
  "http.proxy": "squid:8888",
  "http.proxy.auth.scheme": "BASIC",
  "http.proxy.user": "admin",
  "http.proxy.password": "1234",
```

## ♨️ Using specific JDK

It is sometime necessary for an investigation to replace JDK installed on connect image for example.

Here are some examples:

### 🌀 Azul Zulu JDK

Just use [playground container change-jdk](/playground%20container%20change-jdk) CLI command !

Example:

```bash
$ playground container change-jdk --version 21 --container control-center 
17:03:25 ℹ️ 🤎 Installing Azul JDK 21 on container control-center /usr/lib/jvm/java-11-zulu-openjdk/bin/java
17:03:25 ℹ️ Executing command as root in container control-center with bash
Last metadata expiration check: 0:26:16 ago on Fri May 24 14:37:10 2024.
zulu-repo-1.0.0-1.noarch.rpm                    4.4 kB/s | 3.0 kB     00:00    
Package zulu-repo-1.0.0-1.noarch is already installed.
Dependencies resolved.
Nothing to do.
Complete!
Last metadata expiration check: 0:26:17 ago on Fri May 24 14:37:10 2024.
Dependencies resolved.
================================================================================
 Package                     Architecture Version       Repository         Size
================================================================================
Installing:
 zulu21-jdk                  aarch64      21.0.3-1      zulu-openjdk      4.3 k
Installing dependencies:
 zulu21-ca-doc               aarch64      21.0.3-1      zulu-openjdk      232 k
 zulu21-ca-jdk               aarch64      21.0.3-1      zulu-openjdk       23 k
 zulu21-ca-jdk-headless      aarch64      21.0.3-1      zulu-openjdk       81 M
 zulu21-ca-jre               aarch64      21.0.3-1      zulu-openjdk      354 k
 zulu21-ca-jre-headless      aarch64      21.0.3-1      zulu-openjdk       47 M
 zulu21-doc                  aarch64      21.0.3-1      zulu-openjdk      4.2 k
 zulu21-jdk-headless         aarch64      21.0.3-1      zulu-openjdk      4.3 k
 zulu21-jre                  aarch64      21.0.3-1      zulu-openjdk      4.2 k
 zulu21-jre-headless         aarch64      21.0.3-1      zulu-openjdk      4.2 k

Transaction Summary
================================================================================
Install  10 Packages

Total download size: 128 M
Installed size: 295 M
Downloading Packages:
(1/10): zulu21-ca-jdk-21.0.3-1.aarch64.rpm      180 kB/s |  23 kB     00:00    
(2/10): zulu21-ca-doc-21.0.3-1.aarch64.rpm      1.2 MB/s | 232 kB     00:00    
(3/10): zulu21-ca-jre-21.0.3-1.aarch64.rpm      1.5 MB/s | 354 kB     00:00    
(4/10): zulu21-doc-21.0.3-1.aarch64.rpm          36 kB/s | 4.2 kB     00:00    
(5/10): zulu21-jdk-21.0.3-1.aarch64.rpm          66 kB/s | 4.3 kB     00:00    
(6/10): zulu21-jdk-headless-21.0.3-1.aarch64.rp  36 kB/s | 4.3 kB     00:00    
(7/10): zulu21-jre-21.0.3-1.aarch64.rpm          76 kB/s | 4.2 kB     00:00    
(8/10): zulu21-jre-headless-21.0.3-1.aarch64.rp 100 kB/s | 4.2 kB     00:00    
(9/10): zulu21-ca-jre-headless-21.0.3-1.aarch64 3.2 MB/s |  47 MB     00:14    
(10/10): zulu21-ca-jdk-headless-21.0.3-1.aarch6 5.3 MB/s |  81 MB     00:15    
--------------------------------------------------------------------------------
Total                                           8.4 MB/s | 128 MB     00:15     
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64                1/1 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64                1/1 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                   1/1 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                            1/1 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                   1/1 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                            1/1 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                            1/1 
  Preparing        :                                                        1/1 
  Installing       : zulu21-ca-jre-headless-21.0.3-1.aarch64               1/10 
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64               1/10 
  Installing       : zulu21-ca-jdk-headless-21.0.3-1.aarch64               2/10 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64               2/10 
  Installing       : zulu21-ca-jre-21.0.3-1.aarch64                        3/10 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                        3/10 
  Installing       : zulu21-jre-headless-21.0.3-1.aarch64                  4/10 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                  4/10 
  Installing       : zulu21-ca-doc-21.0.3-1.aarch64                        5/10 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                        5/10 
  Installing       : zulu21-ca-jdk-21.0.3-1.aarch64                        6/10 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                        6/10 
  Installing       : zulu21-doc-21.0.3-1.aarch64                           7/10 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                           7/10 
  Installing       : zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Installing       : zulu21-jre-21.0.3-1.aarch64                           9/10 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                           9/10 
  Installing       : zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64              10/10 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64              10/10 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                 10/10 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                 10/10 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Verifying        : zulu21-ca-doc-21.0.3-1.aarch64                        1/10 
  Verifying        : zulu21-ca-jdk-21.0.3-1.aarch64                        2/10 
  Verifying        : zulu21-ca-jdk-headless-21.0.3-1.aarch64               3/10 
  Verifying        : zulu21-ca-jre-21.0.3-1.aarch64                        4/10 
  Verifying        : zulu21-ca-jre-headless-21.0.3-1.aarch64               5/10 
  Verifying        : zulu21-doc-21.0.3-1.aarch64                           6/10 
  Verifying        : zulu21-jdk-21.0.3-1.aarch64                           7/10 
  Verifying        : zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Verifying        : zulu21-jre-21.0.3-1.aarch64                           9/10 
  Verifying        : zulu21-jre-headless-21.0.3-1.aarch64                 10/10 

Installed:
  zulu21-ca-doc-21.0.3-1.aarch64           zulu21-ca-jdk-21.0.3-1.aarch64       
  zulu21-ca-jdk-headless-21.0.3-1.aarch64  zulu21-ca-jre-21.0.3-1.aarch64       
  zulu21-ca-jre-headless-21.0.3-1.aarch64  zulu21-doc-21.0.3-1.aarch64          
  zulu21-jdk-21.0.3-1.aarch64              zulu21-jdk-headless-21.0.3-1.aarch64 
  zulu21-jre-21.0.3-1.aarch64              zulu21-jre-headless-21.0.3-1.aarch64 

Complete!
17:03:54 ℹ️ Executing command as root in container control-center with bash
17:03:54 ℹ️ Restarting docker container control-center
control-center
17:04:02 ℹ️ Executing command in container control-center with bash
openjdk version "21.0.3" 2024-04-16 LTS
OpenJDK Runtime Environment Zulu21.34+19-CA (build 21.0.3+9-LTS)
OpenJDK 64-Bit Server VM Zulu21.34+19-CA (build 21.0.3+9-LTS, mixed mode, sharing)
```

### ⭕️ Oracle JDK

Here are the steps to follow:

1. Get the Oracle JDK `.rpm` version link you want to install from the [website](https://www.oracle.com/java/technologies/downloads/). In our example, that will be `jdk-8u201-linux-x64.rpm`

2. Add this in your `docker-compose` file:

```yml
  connect:
    build:
      context: ../../connect/connect-filestream-sink/
      args:
        CP_CONNECT_IMAGE: ${CP_CONNECT_IMAGE}
        CP_CONNECT_TAG: ${CP_CONNECT_TAG}
```
WARNING
Make sure to update `context` above with the right path.

3. Create a `Dockerfile` file in `context` directory above (`../../connect/connect-filestream-sink/`).

```yml
ARG CP_CONNECT_IMAGE
ARG CP_CONNECT_TAG
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}
COPY jdk-8u201-linux-x64.rpm /tmp/
USER root
RUN yum -y install /tmp/jdk-8u201-linux-x64.rpm && alternatives --set java /usr/java/jdk1.8.0_201-amd64/jre/bin/java && rm /tmp/jdk-8u201-linux-x64.rpm
USER appuser
```

WARNING
Make sure to update `alternatives --set java` above with the right path.

4. Verify the correct JDK version is installed once your test is started:

```bash
docker exec connect java -version
java version "1.8.0_201"
Java(TM) SE Runtime Environment (build 1.8.0_201-b09)
Java HotSpot(TM) 64-Bit Server VM (build 25.201-b09, mixed mode)
```

## 🏎️ Performance testing

Here are some tips and tricks to create reproduction models that require high volume of data.

TIP
It is highly recommended to enable [JMX Grafana](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%93%8a-enabling-jmx-grafana) when you're doing performance testing, to see CPU/Memory and all JMX metrics.

### 👈 All sink connectors

Injecting lot of records into topic(s) is really easy using [🛠 Bootstrap reproduction model](https://kafka-docker-playground.io/#/reusables?id=%f0%9f%9b%a0-bootstrap-reproduction-model) with [♨️ Java producers](https://kafka-docker-playground.io/#/reusables?id=%e2%99%a8%ef%b8%8f-java-producers) option.

To inject infinite number of requests as fast as possible, use `NB_MESSAGES=-1` and `MESSAGE_BACKOFF=0` and use `-d` to run the injection in the background:

```bash
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
```

If load is not enough, you can start multiple producers in parallel:

```bash
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic2" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic2" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic2" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic2" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -e NB_MESSAGES=-1 -e MESSAGE_BACKOFF=0 -e TOPIC="test-topic2" -d producer-repro-12345 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
```

### 👉 Oracle

For all Oracle CDC and JDBC source connector with Oracle examples, you can easily inject load in table using, the following steps.

You can enable this by setting flag `--enable-sql-datagen`, it will start inserting rows at the end of the example for a duration that you can configure:

Example:

```bash
DURATION=10
log "Injecting data for $DURATION minutes"
docker exec -d oracle-datagen bash -c "java ${JAVA_OPTS} -jar oracle-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username C##MYUSER --password mypassword --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin $DURATION"
```

TIP
You can increase throughtput with `maxPoolSize`.

### 👉 Microsoft SQL Server

For all Debezium and JDBC source connector with Microsoft SQL Server examples, you can easily inject load in table using, the following steps.

You can enable this by setting flag `enable-sql-datagen`, it will start inserting rows at the end of the example for a duration that you can configure:

Example:

```bash
DURATION=10
log "Injecting data for $DURATION minutes"
docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --username sa --password 'Password!' --connectionUrl 'jdbc:sqlserver://sqlserver:1433;databaseName=testDB;encrypt=false' --maxPoolSize 10 --durationTimeMin $DURATION"
```

TIP
You can increase throughtput with `maxPoolSize`.

### 👉 PostgreSQL

For all Debezium and JDBC source connector with PostgreSQL examples, you can easily inject load in table using, the following steps.

You can enable this by setting flag `enable-sql-datagen`, it will start inserting rows at the end of the example for a duration that you can configure:

Example:

```bash
DURATION=10
log "Injecting data for $DURATION minutes"
docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --connectionUrl 'jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false' --maxPoolSize 10 --durationTimeMin $DURATION"
```

TIP
You can increase throughtput with `maxPoolSize`.

### 👉 MySQL

For all Debezium and JDBC source connector with MySQL examples, you can easily inject load in table using, the following steps.

You can enable this by setting flag `enable-sql-datagen`, it will start inserting rows at the end of the example for a duration that you can configure:

Example:

```bash
DURATION=10
log "Injecting data for $DURATION minutes"
docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --connectionUrl 'jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false' --maxPoolSize 10 --durationTimeMin $DURATION"
```

TIP
You can increase throughtput with `maxPoolSize`.

### 👉 MongoDB

Here is an example that I used to setup a reproduction environment where I inject 250 (`REQ`) req/s on 13 (`NB_COLLECTIONS`) collections. 
It is sending 50000 (`TOTAL_REQ`) records per collection.
The size of the record can be ajusted by changing the payload `{ _id : "Document " + j + "_" + i, first_name : 'john', last_name : 'hope', email : 'john@email/com', timestamp: new Date().getTime() }`

```bash
function inject () {
docker exec -i mongodb mongosh << EOF
use kafka
var counter = 0;
var j = 0;
while(counter < $TOTAL_REQ) {
var bulk = db.collection$i.initializeUnorderedBulkOp();
for (var i = 0; i < $REQ; i++) {
    bulk.insert({ _id : "Document " + j + "_" + i, first_name : 'john', last_name : 'hope', email : 'john@email/com', timestamp: new Date().getTime() });
}
bulk.execute();
j++;
counter+=$REQ;
sleep(1000);
}
EOF
date end_collection$i.txt
}

REQ=250
NB_COLLECTIONS=13
TOTAL_REQ=50000
for((i=1;i<=$NB_COLLECTIONS;i++)); do
  log "Inserting $TOTAL_REQ documents ($REQ req/second) on collection$i"
  inject /dev/null 2>&1 &
done

log "Wait for $TOTAL_REQ records to be processed"
playground topic consume --topic myprefix.kafka.collection1 --min-expected-messages $TOTAL_REQ --timeout 80000

log "mongo injection ended at"
cat end_collection1.txt
```

Then you can use [MongoDB source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mongodb-source) connector:

```bash
playground connector create-or-update --connector mongodb-source << EOF
{
  "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
  "tasks.max" : "1",
  "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
  "database": "kafka",
  "mongo.errors.log.enable": "true",
  "topic.prefix":"myprefix",

  "output.format.key":"json",
  "output.format.value":"json",
  "output.json.formatter":"com.mongodb.kafka.connect.source.json.formatter.SimplifiedJson",
  "output.schema.infer.value":"false",
  "value.converter": "org.apache.kafka.connect.storage.StringConverter",

  "poll.await.time.ms": "10000",
  "poll.max.batch.size": "50",

  "batch.size":"50",
  "publish.full.document.only":"true",
  "change.stream.full.document":"updateLookup",

  "heartbeat.interval.ms": "5000",

  "_producer.override.linger.ms":"500",
  "_producer.override.batch.size":"2000000",
  "producer.override.client.id":"mongo-producer",
  "_producer.override.compression.type": "lz4"
}
EOF
```

### 👉 MQTT

In order to generate perf injection, you can use [Solace SDKPerf tool](https://docs.solace.com/API/SDKPerf/SDKPerf.htm), [download](https://solace.com/downloads/?fwp_downloads_types=other) it first.

(optional) Add in your docker-compose file a EQMX MQTT broker:

```yml
  emqx:
    image: emqx/emqx:latest
    hostname: emqx
    container_name: emqx
    environment:
    - "EMQX_NAME=emqx"
    - "EMQX_HOST=emqx"
    - "MQTT_SESSION_MAX_INFLIGHT=64" 
    ports:
      - 1883:1883
      - 18083:18083
```

Note: EQMX dashboard is available on http://localhost:18083/ (`admin`/`public`)

Send MQTT messages at 3000 messages/sec with QOS 1 (`"mqtt.topics":"test_mqtt"`):

```bash
./sdkperf-mqtt-8.4.10.6/sdkperf_mqtt.sh -cip=localhost:1883 -ptl=test_mqtt -msa=100 -mn=5000000 -mr=3000 -mpq=1
```

Then you can use [MQTT source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mqtt-source) connector:

```bash
log "Creating MQTT Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
               "tasks.max": "1",
               "mqtt.server.uri": "tcp://emqx:1883",
               "mqtt.topics":"test_mqtt",
               "kafka.topic":"mqtt-source-1",
               "mqtt.qos": "1",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",

               "records.buffer.queue.size": "10000",
               "records.buffer.queue.max.batch.size": "100",
               "records.buffer.queue.empty.timeout": "10" 
          }' \
     http://localhost:8083/connectors/source-mqtt/config | jq .
```


# 🎁 Tips & Tricks

Below is a collection of tips and tricks

# 🐳 Docker tips

## Tail container logs

Example with `connect` container:

```bash
docker container logs --tail=100 -f connect
```

or use [🧠 CLI](/cli) with:

```bash
playground container logs -c connect
```

## Redirect all container logs to a file

Example with `connect` container:

```bash
docker container logs connect connect.log 2>&1
```

or use [🧠 CLI](/cli) with:

```bash
playground container logs -c connect -o code
```

Output:

```bash
23:10:30 ℹ️ Opening /tmp/connect-2023-02-27-23-10-30.log with editor code
```

## SSH into container

Example with `connect` container:

```bash
docker exec -it connect bash
```

or use [🧠 CLI](/cli) with:

```bash
playground container ssh -c connect
```

## Kill all docker containers

```bash
docker rm -f $(docker ps -qa)
```

or use [🧠 CLI](/cli) with:

```bash
playground container kill-all
```

## Recover from Docker error `max depth exceeded`

When running an example you get:

```log
docker: Error response from daemon: max depth exceeded.
```

This happens from time to time and the only way to resolve this, as far as I know, is to remove all images using:

```bash
docker image rm $(docker image list | grep -v "oracle/database"  | grep -v "db-prebuilt" | awk 'NR>1 {print $3}') -f
```

## Run some commands

Example with `connect` container:

```bash
docker exec connect bash -c "whoami"
```

or use [🧠 CLI](/cli) with:

```bash
playground container exec -c connect -d "whoami"
```

## Run some commands as root

Example with `connect` container:

```bash
docker exec --privileged --user root connect bash -c "whoami"
```

or use [🧠 CLI](/cli) with:

```bash
playground container exec -c connect -d "whoami" --root
```

## Get IP address of running containers

```bash
docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)
```

Example:

```
/control-center - 172.21.0.6
/connect - 172.21.0.5
/schema-registry - 172.21.0.4
/broker - 172.21.0.2
/zookeeper - 172.21.0.3
```

or use [🧠 CLI](/cli) with:

```bash
playground container get-ip-addresses
```

## Get number of records in a topic

```bash
docker exec -i broker bash << EOF
kafka-run-class kafka.tools.GetOffsetShell --broker-list broker:9092 --topic a-topic --time -1 | awk -F ":" '{sum += \$3} END {print sum}'
EOF
```

or use [🧠 CLI](/cli) with:

```bash
$  playground topic get-number-records --help
playground topic get-number-records - 💯 Get number of records in a topic.

== Usage ==
  playground topic get-number-records [OPTIONS]
  playground topic get-number-records --help | -h

== Options ==
  --topic, -t TOPIC (required)
    Topic name.

  --help, -h
    Show this help

Examples:
  playground get-number-records --topic a-topic
  playground get-number-records -t a-topic
```

## Check Kafka Connect offsets topic

```bash
docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --property print.timestamp=true
```

or use [🧠 CLI](/cli) with:

```bash
$  playground topic display-connect-offsets --help
playground topic display-connect-offsets - 🔺 Display content of connect offsets topic.

== Usage ==
  playground topic display-connect-offsets
  playground topic display-connect-offsets --help | -h

== Options ==
  --help, -h
    Show this help
```

