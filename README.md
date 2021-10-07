<!-- omit in toc -->
# <img src="https://www.docker.com/sites/default/files/d8/2019-07/vertical-logo-monochromatic.png" width="24"> <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="24"> kafka-docker-playground

Playground for Kafka/Confluent Docker experimentations...

![Github CI](https://github.com/vdesabou/kafka-docker-playground/workflows/CI/badge.svg)![success tests](https://img.shields.io/badge/success%20tests-1039%2F1100-red)![connector tested](https://img.shields.io/badge/connector%20tested-125-green)![cp versions tested](https://img.shields.io/badge/cp%20version%20tested-%205.5.6%206.0.3%206.1.2%206.2.1-green)![last run](https://img.shields.io/badge/last%20run-2021--10--07%2011:35-green)
![GitHub issues by-label](https://img.shields.io/github/issues/vdesabou/kafka-docker-playground/bug%20🔥)![GitHub issues by-label](https://img.shields.io/github/issues/vdesabou/kafka-docker-playground/enhancement%20✨)
![GitHub repo size](https://img.shields.io/github/repo-size/vdesabou/kafka-docker-playground)
[![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-908a85?logo=gitpod)](https://gitpod.io/#https://github.com/vdesabou/kafka-docker-playground)

- [👾 Playgrounds](#-playgrounds)
  - [Connectors](#connectors)
  - [☁️ Confluent Cloud](#️-confluent-cloud)
  - [🔄 Confluent Replicator and Mirror Maker 2](#-confluent-replicator-and-mirror-maker-2)
  - [🔐 Environments](#-environments)
  - [Confluent Commercial](#confluent-commercial)
  - [CP-Ansible Playground](#cp-ansible-playground)
  - [👾 Other Playgrounds](#-other-playgrounds)
- [🎓 How to use](#-how-to-use)
  - [0️⃣ Prerequisites](#0️⃣-prerequisites)
  - [🐳 Recommended Docker settings](#-recommended-docker-settings)
  - [🌩 Running on AWS EC2 instance](#-running-on-aws-ec2-instance)
  - [<img src="https://gitpod.io/static/media/gitpod.2cdd910d.svg" width="15"> Running on Gitpod](#-running-on-gitpod)


# 👾 Playgrounds

## Connectors

Quick start examples from Confluent [docs](https://docs.confluent.io/current/connect/managing/index.html) but in Docker version for ease of use.

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"> [ActiveMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-active-mq-sink) (also with 🔑 mTLS) 

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-activemq/sink) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3757012352) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"> [ActiveMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-active-mq-source) (also with 🔑  mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-11.0.8-pink)](https://docs.confluent.io/kafka-connect-activemq-source/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3757012352) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"> [Amazon CloudWatch Logs Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-cloudwatch-logs-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.1-pink)](https://docs.confluent.io/kafka-connect-aws-cloudwatch-logs/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloudwatch_logs.svg" width="15"> [Amazon CloudWatch Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-cloudwatch-metrics-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.6-pink)](https://docs.confluent.io/kafka-connect-aws-cloudwatch-metrics/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/dynamodb.svg" width="15"> [Amazon DynamoDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-dynamodb-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.2-pink)](https://docs.confluent.io/kafka-connect-aws-dynamodb/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kinesis.svg" width="15"> [Amazon Kinesis Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-kinesis-source) (also with 🌐 proxy)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.3.7-pink)](https://docs.confluent.io/kafka-connect-kinesis/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/aws_redshift.png" width="15"> [Amazon Redshift Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-redshift-sink) 

![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/aws_redshift.png" width="15"> [Amazon Redshift Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-aws-redshift-source) (using JDBC) 

![not tested](https://img.shields.io/badge/CI-not%20tested!-violet)

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"> [Amazon S3 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink) (also with 🌐 proxy)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.0.3-pink)](https://docs.confluent.io/kafka-connect-s3-sink/current/index.html) [![CI fail](https://img.shields.io/badge/CI-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/935) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/s3.png" width="15"> [Amazon S3 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.9-pink)](https://docs.confluent.io/kafka-connect-s3-source/current/index.html) [![CI fail](https://img.shields.io/badge/CI-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/921) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sqs.svg" width="15"> [Amazon SQS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-sqs-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.1-pink)](https://docs.confluent.io/kafka-connect-sqs/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650502) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/amps.png" width="15"> [AMPS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-amps-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.0_preview-pink)](https://docs.confluent.io/current/connect/kafka-connect-amps/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kudu.png" width="15"> [Apache Kudu Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-kudu-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.2-pink)](https://docs.confluent.io/kafka-connect-kudu/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650923) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kudu.png" width="15"> [Apache Kudu Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-kudu-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.2-pink)](https://docs.confluent.io/kafka-connect-kudu/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650923) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/lambda.svg" width="15"> [AWS Lambda Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-lambda-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.1-pink)](https://docs.confluent.io/current/connect/kafka-connect-aws-lambda/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/blob_storage.png" width="15"> [Azure Blob Storage Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-blob-storage-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.6.3-pink)](https://docs.confluent.io/kafka-connect-azure-blob-storage-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/blob_storage.png" width="15"> [Azure Blob Storage Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-blob-storage-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.9-pink)](https://docs.confluent.io/kafka-connect-azure-blob-storage-source/current/index.html)  [![CP 5.5.6](https://img.shields.io/badge/CI-CP%205.5.6-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3819872288) [![CP 6.0.3](https://img.shields.io/badge/CI-CP%206.0.3-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3819874214) [![issue 778](https://img.shields.io/badge/CI-CP%206.1.2-red)](https://github.com/vdesabou/kafka-docker-playground/issues/778) [![issue 778](https://img.shields.io/badge/CI-CP%206.2.1-red)](https://github.com/vdesabou/kafka-docker-playground/issues/778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"> [Azure Cosmos DB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-cosmosdb-sink)

 ![license](https://img.shields.io/badge/-Microsoft%20Corporation-lightgrey) [![version](https://img.shields.io/badge/v-1.1.0-pink)](https://github.com/microsoft/kafka-connect-cosmosdb)  [![issue 1397](https://img.shields.io/badge/CI-CP%205.5.6-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1397) [![CP 6.0.3](https://img.shields.io/badge/CI-CP%206.0.3-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778206609) [![CP 6.1.2](https://img.shields.io/badge/CI-CP%206.1.2-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207253) [![CP 6.2.1](https://img.shields.io/badge/CI-CP%206.2.1-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cosmosdb.png" width="15"> [Azure Cosmos DB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-cosmosdb-source)

 ![license](https://img.shields.io/badge/-Microsoft%20Corporation-lightgrey) [![version](https://img.shields.io/badge/v-1.1.0-pink)](https://github.com/microsoft/kafka-connect-cosmosdb)  [![issue 1396](https://img.shields.io/badge/CI-CP%205.5.6-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1396) [![CP 6.0.3](https://img.shields.io/badge/CI-CP%206.0.3-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778206609) [![CP 6.1.2](https://img.shields.io/badge/CI-CP%206.1.2-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207253) [![CP 6.2.1](https://img.shields.io/badge/CI-CP%206.2.1-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_lake_gen1.png" width="15"> [Azure Data Lake Storage Gen1 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-data-lake-storage-gen1-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.6.3-pink)](https://docs.confluent.io/kafka-connect-azure-data-lake-gen1-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650701) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_lake_gen1.png" width="15"> [Azure Data Lake Storage Gen2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-data-lake-storage-gen2-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.6.3-pink)](https://docs.confluent.io/kafka-connect-azure-data-lake-gen2-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650701) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/event_hubs.png" width="15"> [Azure Event Hubs Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-event-hubs-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.1-pink)](https://docs.confluent.io/kafka-connect-azure-event-hubs/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3757013055) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/azure_functions.png" width="15"> [Azure Functions Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-functions-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.12-pink)](https://docs.confluent.io/kafka-connect-azure-functions/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650701) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/search.png" width="15"> [Azure Search Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-cognitive-search-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.1-pink)](https://docs.confluent.io/kafka-connect-azure-search/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650701) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/service_bus.png" width="15"> [Azure Service Bus Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-service-bus-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.2-pink)](https://docs.confluent.io/kafka-connect-azure-servicebus/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650701) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_data_warehouse.png" width="15"> [Azure SQL Data Warehouse Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-azure-sql-data-warehouse-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.4-pink)](https://docs.confluent.io/current/connect/kafka-connect-azure-sql-dw/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cassandra.png" width="15"> [Cassandra Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cassandra-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-cassandra/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649826) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/couchbase.svg" width="15"> [Couchbase Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-couchbase-sink)

 ![license](https://img.shields.io/badge/-Couchbase,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-4.1.2-pink)](https://docs.couchbase.com/kafka-connector/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649826) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/couchbase.svg" width="15"> [Couchbase Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-couchbase-source)

 ![license](https://img.shields.io/badge/-Couchbase,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-4.1.2-pink)](https://docs.couchbase.com/kafka-connector/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649826) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"> [Debezium CDC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-sqlserver-source)

 ![license](https://img.shields.io/badge/-Debezium%20Community-lightgrey) [![version](https://img.shields.io/badge/v-1.7.0-pink)](http://debezium.io/docs/connectors/sqlserver/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3796071615) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.jpg" width="15"> [Debezium CDC MySQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-mysql-source)

 ![license](https://img.shields.io/badge/-Debezium%20Community-lightgrey) [![version](https://img.shields.io/badge/v-1.7.0-pink)](http://debezium.io/docs/connectors/mysql/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3796071615) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"> [Debezium CDC PostgreSQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-postgresql-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Debezium%20Community-lightgrey) [![version](https://img.shields.io/badge/v-1.7.0-pink)](http://debezium.io/docs/connectors/postgresql/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3796071615) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.jpg" width="15"> [Debezium CDC MongoDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-debezium-mongodb-source)

 ![license](https://img.shields.io/badge/-Debezium%20Community-lightgrey) [![version](https://img.shields.io/badge/v-1.7.0-pink)](http://debezium.io/docs/connectors/mongodb/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3796071615) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_diode.jpg" width="15"> [Data Diode Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadiode-source-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.1-pink)](https://docs.confluent.io/current/connect/kafka-connect-data-diode/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649903) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/data_diode.jpg" width="15"> [Data Diode Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadiode-source-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.1-pink)](https://docs.confluent.io/current/connect/kafka-connect-data-diode/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649903) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/datadog.png" height="15"> [Datadog Metrics Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-datadog-metrics-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.6-pink)](https://docs.confluent.io/kafka-connect-datadog-metrics/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651081) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/elasticsearch.png" width="15"> [ElasticSearch Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-elasticsearch-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-11.1.2-pink)](https://docs.confluent.io/kafka-connect-elasticsearch/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649903) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/filepulse.png" width="15"> [FilePulse Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-filepulse-source)

 ![license](https://img.shields.io/badge/-StreamThoughts-lightgrey) [![version](https://img.shields.io/badge/v-2.3.0-pink)](https://github.com/streamthoughts/kafka-connect-file-pulse)  [![CP 5.5.6](https://img.shields.io/badge/CI-CP%205.5.6-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3784236663) [![issue 1371](https://img.shields.io/badge/CI-CP%206.0.3-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1371) [![issue 1371](https://img.shields.io/badge/CI-CP%206.1.2-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1371) [![issue 1371](https://img.shields.io/badge/CI-CP%206.2.1-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1371) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spool_dir.png" width="15"> [FileStream Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-filestream-source)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spool_dir.png" width="15"> [FileStream Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-filestream-sink)
* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ftps.png" height="15"> [FTPS Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ftps-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.3_preview-pink)](https://docs.confluent.io/current/connect/kafka-connect-ftps/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ftps.png" height="15"> [FTPS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ftps-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.3_preview-pink)](https://docs.confluent.io/current/connect/kafka-connect-ftps/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/pivotal_gemfire.png" width="15"> [Gemfire Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-pivotal-gemfire-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.6-pink)](https://docs.confluent.io/kafka-connect-pivotal-gemfire/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/github.png" width="15"> [Github Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-github-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.1.2-pink)](https://docs.confluent.io/kafka-connect-github/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3748979827) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/bigquery.png" width="15"> [Google BigQuery Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-bigquery-sink)

 ![license](https://img.shields.io/badge/-WePay-lightgrey) [![version](https://img.shields.io/badge/v-2.1.7-pink)](https://docs.confluent.io/kafka-connect-bigquery/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3748979675) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_bigtable.png" width="15"> [Google Cloud BigTable Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-bigtable-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.10-pink)](https://docs.confluent.io/kafka-connect-gcp-bigtable/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650582) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cloud_functions.png" width="15"> [Google Cloud Functions Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-cloud-functions-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.5-pink)](https://docs.confluent.io/kafka-connect-gcp-functions/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650502) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcp_pubsub.png" width="15"> [Google Cloud Pub/Sub Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-pubsub-source) (also with 🌐 proxy)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.0-pink)](https://docs.confluent.io/kafka-connect-gcp-pubsub/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650582) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spanner.png" width="15"> [Google Cloud Spanner Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-spanner-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.7-pink)](https://docs.confluent.io/kafka-connect-gcp-spanner/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651081) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcs.png" width="15"> [Google Cloud Storage Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-gcs-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-5.5.10-pink)](https://docs.confluent.io/kafka-connect-gcs-sink/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650582) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/gcs.png" width="15"> [Google Cloud Storage Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-gcs-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.9-pink)](https://docs.confluent.io/current/connect/kafka-connect-gcs-source/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3819877316) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/firebase.svg" width="15"> [Google Firebase Realtime Database Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-firebase-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-firebase/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651081) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/firebase.svg" width="15"> [Google Firebase Realtime Database Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-firebase-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-firebase/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651081) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hbase.png" width="15"> [HBase Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hbase-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.10-pink)](https://docs.confluent.io/kafka-connect-hbase/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649826) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"> [HDFS 2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs2-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.9-pink)](https://docs.confluent.io/kafka-connect-hdfs2-source/current/index.html) [![CI fail](https://img.shields.io/badge/CI-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1168) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"> [HDFS 3 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs3-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.9-pink)](https://docs.confluent.io/kafka-connect-hdfs3-source/current/index.html) [![CI fail](https://img.shields.io/badge/CI-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1175) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"> [HDFS 2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs2-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.1.1-pink)](https://docs.confluent.io/kafka-connect-hdfs/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649954) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/hdfs_2.svg" width="15"> [HDFS 3 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs3-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.5-pink)](https://docs.confluent.io/kafka-connect-hdfs3-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3771624213) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/http.png" width="15"> [HTTP Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-http-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.5.0-pink)](https://docs.confluent.io/kafka-connect-http/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650856) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibm_mq.png" width="15"> [IBM MQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ibm-mq-sink) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/sink) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649954) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibm_mq.png" width="15"> [IBM MQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-ibm-mq-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-11.0.8-pink)](https://docs.confluent.io/kafka-connect-ibmmq-source/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649954) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/influxdb.svg" width="15"> [InfluxDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-influxdb-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.2-pink)](https://docs.confluent.io/kafka-connect-influxdb/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650008) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/influxdb.svg" width="15"> [InfluxDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-influxdb-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.2-pink)](https://docs.confluent.io/kafka-connect-influxdb/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650008) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/cockroachdb.png" width="15"> [JDBC CockroachDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-cockroachdb-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibmdb2.png" width="15"> [JDBC IBM DB2 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-ibmdb2-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/ibmdb2.png" width="15"> [JDBC IBM DB2 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-ibmdb2-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.jpg" width="15"> [JDBC MySQL Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-mysql-sink) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_11.jpg" width="15"> [JDBC Oracle 11 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle11-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"> [JDBC Oracle 12 Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle12-sink) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207480) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"> [JDBC Oracle 19c Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle19-sink) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207493) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"> [JDBC PostGreSQL Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-postgresql-sink) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"> [JDBC Microsoft SQL Server Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sqlserver-sink) (also with 🔑 SSL)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mysql.jpg" width="15"> [JDBC MySQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-mysql-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_11.jpg" width="15"> [JDBC Oracle 11 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle11-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"> [JDBC Oracle 12 Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle12-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207480) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"> [JDBC Oracle 19c Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-oracle19-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207493) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/postgresql.png" width="15"> [JDBC PostGreSQL Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-postgresql-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207415) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sql_server.png" width="15"> [JDBC Microsoft SQL Server Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-sqlserver-source) (also with 🔑 SSL)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" height="15">  [JDBC Snowflake Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-snowflake-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207809) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" height="15">  [JDBC Snowflake Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-snowflake-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207809) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/vertica.png" width="15"> [JDBC Vertica Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-vertica-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.2.4-pink)](https://docs.confluent.io/kafka-connect-jdbc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3778207450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/jira.png" width="15"> [JIRA Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jira-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.6_preview-pink)](https://docs.confluent.io/kafka-connect-jira/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/activemq.png" width="15"> [JMS ActiveMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-active-mq-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650111) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.jpg" width="15"> [JMS Solace Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-solace-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650111) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"> [JMS TIBCO EMS Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-tibco-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649903) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"> [JMS TIBCO EMS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-tibco-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-11.0.8-pink)](https://docs.confluent.io/kafka-connect-jms-source/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649903) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/weblogic.png" width="15"> [JMS Oracle Weblogic Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-weblogic-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/kafka-connect-jms-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3757013731) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/weblogic.png" width="15"> [JMS Oracle Weblogic Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jms-weblogic-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-11.0.8-pink)](https://docs.confluent.io/kafka-connect-weblogic-source/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651379) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mapr.png" height="15"> [Mapr Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mapr-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc-lightgrey) [![version](https://img.shields.io/badge/v-1.1.3-pink)](https://docs.confluent.io/kafka-connect-maprdb/current/index.html)  [![CP 5.5.6](https://img.shields.io/badge/CI-CP%205.5.6-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3779175842) [![issue 1401](https://img.shields.io/badge/CI-CP%206.0.3-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1401) [![issue 1401](https://img.shields.io/badge/CI-CP%206.1.2-red)](https://github.com/vdesabou/kafka-docker-playground/issues/1401) [![CP 6.2.1](https://img.shields.io/badge/CI-CP%206.2.1-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3779175890) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/marketo.png" height="15"> [Marketo Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-marketo-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.0_preview-pink)](https://docs.confluent.io/current/connect/kafka-connect-marketo/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649826) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/minio.png" height="15"> [Minio Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-minio-s3-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-10.0.3-pink)](https://docs.confluent.io/kafka-connect-s3-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649826) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.jpg" width="15"> [MongoDB Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mongodb-sink)

 ![license](https://img.shields.io/badge/-MongoDB-lightgrey) [![version](https://img.shields.io/badge/v-1.6.1-pink)](https://github.com/mongodb/mongo-kafka/blob/master/README.md) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.jpg" width="15"> [MongoDB Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mongodb-source)

 ![license](https://img.shields.io/badge/-MongoDB-lightgrey) [![version](https://img.shields.io/badge/v-1.6.1-pink)](https://github.com/mongodb/mongo-kafka/blob/master/README.md) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mqtt.png" width="15"> [MQTT Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mqtt-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.1-pink)](https://docs.confluent.io/kafka-connect-mqtt/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mqtt.png" width="15"> [MQTT Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-mqtt-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.4.1-pink)](https://docs.confluent.io/kafka-connect-mqtt/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/neo4j.png" width="15"> [Neo4j Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-neo4j-sink)

 ![license](https://img.shields.io/badge/-Neo4j,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.9-pink)](https://neo4j-contrib.github.io/neo4j-streams/#_kafka_connect) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/omnisci.png" width="15"> [OmniSci Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-omnisci-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.3-pink)](https://docs.confluent.io/current/connect/kafka-connect-omnisci/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"> [Oracle CDC](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle12-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.3.0-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3760464314) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/oracle_12.jpg" width="15"> [Oracle CDC](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle19-source) (also with 🔑 SSL and mTLS)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.3.0-pink)](https://docs.confluent.io/kafka-connect-oracle-cdc/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3760464361) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/pagerduty.png" width="15"> [PagerDuty Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-pagerduty-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.2-pink)](https://docs.confluent.io/current/connect/kafka-connect-pagerduty/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651081) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/prometheus.png" height="15">  [Prometheus Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-prometheus-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.6_preview-pink)](https://docs.confluent.io/kafka-connect-prometheus-metrics/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650502) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/rabbitmq.svg" width="15"> [RabbitMQ Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-rabbitmq-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.5.2-pink)](https://docs.confluent.io/kafka-connect-rabbitmq-sink/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650778) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/rabbitmq.svg" width="15">  [RabbitMQ Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-rabbitmq-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.5.2-pink)](https://docs.confluent.io/kafka-connect-rabbitmq-source/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650410) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/redis.jpg" width="15"> [Redis Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-redis-sink)

 ![license](https://img.shields.io/badge/-Jeremy%20Custenborder-lightgrey) [![version](https://img.shields.io/badge/v-0.0.2.13-pink)](https://docs.confluent.io/current/connect/kafka-connect-redis/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650410) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce Bulk API Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-bulkapi-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce-bulk-api/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce Bulk API Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-bulkapi-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce-bulk-api/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce CDC Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce Platform Events Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-platform-events-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce Platform Events Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-platform-events-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce PushTopics Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-pushtopics-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/salesforce.png" height="15"> [SalesForce SObject Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-sobject-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.10.3-pink)](https://docs.confluent.io/kafka-connect-salesforce/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649706) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"> [ServiceNow Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-servicenow-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.3.5-pink)](https://docs.confluent.io/current/connect/kafka-connect-servicenow/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3760463017) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"> [ServiceNow Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-servicenow-source) (also with 🌐 proxy)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.3.5-pink)](https://docs.confluent.io/current/connect/kafka-connect-servicenow/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3760463017) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sftp.png" width="15"> [SFTP Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-sftp-sink) (also with 🔑 Kerberos)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.3.6-pink)](https://docs.confluent.io/kafka-connect-sftp/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650450) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/sftp.png" width="15"> [SFTP Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-sftp-source) (also with 🔑 Kerberos)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.3.6-pink)](https://docs.confluent.io/kafka-connect-sftp/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650410) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snmp_trap.png" width="15"> [SNMP Trap Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-snmp-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.1.2-pink)](https://docs.confluent.io/current/connect/kafka-connect-snmp-trap/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649954) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/snowflake.png" height="15">  [Snowflake Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-snowflake-sink)

 ![license](https://img.shields.io/badge/-Snowflake,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.5.5-pink)](https://docs.snowflake.net/manuals/user-guide/kafka-connector.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651509) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.jpg" width="15"> [Solace Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-solace-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/kafka-connect-solace/current/sink/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650410) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/solace.jpg" width="15"> [Solace Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-solace-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-solace/source) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650410) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.jpg" width="15"> [Splunk Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-splunk-sink)

 ![license](https://img.shields.io/badge/-Splunk-lightgrey) [![version](https://img.shields.io/badge/v-2.0.2-pink)](https://docs.confluent.io/current/connect/kafka-connect-splunk/splunk-sink) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649757) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.jpg" width="15"> [Splunk Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-splunk-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.3-pink)](https://docs.confluent.io/current/connect/kafka-connect-splunk/splunk-source/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649757) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/splunk.jpg" width="15"> [Splunk S2S Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-splunk-s2s-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.3-pink)](https://docs.confluent.io/kafka-connect-splunk-s2s/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649757) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/spool_dir.png" width="15"> [Spool Dir Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-spool-dir-source)

 ![license](https://img.shields.io/badge/-Jeremy%20Custenborder-lightgrey) [![version](https://img.shields.io/badge/v-2.0.62-pink)](https://docs.confluent.io/kafka-connect-spooldir/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649757) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/syslog.png" width="15"> [Syslog Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-syslog-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.3.4-pink)](https://docs.confluent.io/current/connect/kafka-connect-syslog/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807649757) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"> [TIBCO EMS Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-tibco-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-2.0.0-pink)](https://docs.confluent.io/kafka-connect-tibco/current/sink/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/tibco_ems.png" width="15"> [TIBCO EMS Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-tibco-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.2.0-pink)](https://docs.confluent.io/current/connect/kafka-connect-tibco/source) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650169) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/vertica.png" width="15"> [Vertica Sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-vertica-sink)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc-lightgrey) [![version](https://img.shields.io/badge/v-1.2.5-pink)](https://docs.confluent.io/kafka-connect-vertica/current/index.html) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807650502) 

* <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/zendesk.png" width="15"> [Zendesk Source](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-zendesk-source)

 ![license](https://img.shields.io/badge/-Confluent,%20Inc.-lightgrey) [![version](https://img.shields.io/badge/v-1.0.6-pink)](https://docs.confluent.io/kafka-connect-zendesk/current/) [![CI ok](https://img.shields.io/badge/CI-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3807651081) 


\* You can change default connector version by setting `CONNECTOR_TAG` environment variable before starting a test, get more details [here](https://github.com/vdesabou/kafka-docker-playground/wiki/How-to-run#default-connector-version)

## ☁️ Confluent Cloud

<!-- omit in toc -->
### [Confluent Cloud Demo](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/ccloud-demo) <!-- {docsify-ignore} -->

  - How to connect your components to Confluent Cloud
  - How to monitor your Confluent Cloud cluster
  - How to restrict access
  - etc...

![Diagram](https://github.com/vdesabou/kafka-docker-playground/raw/master/ccloud/ccloud-demo/images/diagram.png)

<!-- omit in toc -->
### 🔗 Kafka Connectors connected to Confluent Cloud <!-- {docsify-ignore} -->

  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/kinesis.svg" width="15"> [AWS Kinesis](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-aws-kinesis-source) source
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"> [ServiceNow](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-servicenow-source) source
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/servicenow.png" width="15"> [ServiceNow](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-servicenow-sink) sink
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/mongodb.jpg" width="15"> [MongoDB](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-debezium-mongodb-source) source
  - <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/firebase.svg" width="15"> [Firebase](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-gcp-firebase-sink)

<!-- omit in toc -->
### Other <!-- {docsify-ignore} -->

  - Using [cp-ansible](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/cp-ansible-playground/) with Confluent Cloud
  - Using [cp-helm-charts](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/cp-helm-chart/) with Confluent Cloud
  - Using [confluent operator](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/operator/) with Confluent Cloud
  - Demo using [dabz/ccloudexporter](https://github.com/Dabz/ccloudexporter) in order to pull [Metrics API](https://docs.confluent.io/current/cloud/metrics-api.html) data from Confluent Cloud cluster and export it to Prometheus (Grafana dashboard is also available)
  - <img src="https://www.pngitem.com/pimgs/m/33-335825_-net-core-logo-png-transparent-png.png" width="15"> [.NET](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-dotnet) client (producer/consumer)
  - <img src="https://github.com/confluentinc/examples/raw/5.4.1-post/clients/cloud/images/go.png" width="15"> [Go](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-go) client (producer/consumer)
  - <img src="https://kafka.js.org/img/kafkajs-logoV2.svg" width="15"> [KafkaJS](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-kafkajs) client (producer/consumer)
  - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/c/c3/Python-logo-notext.svg/110px-Python-logo-notext.svg.png" width="15"> [Python](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-python) client (producer/consumer)
  - <img src="https://vectorified.com/images/admin-icon-png-14.png" width="15"> [kafka-admin](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/kafka-admin) Managing topics and ACLs using [matt-mangia/kafka-admin](https://github.com/matt-mangia/kafka-admin)
  - <img src="https://img.icons8.com/cotton/2x/synchronize--v1.png" width="15"> Confluent Replicator [OnPrem to cloud and Cloud to Cloud examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/replicator)
  - <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="15"> [Multi-Cluster Schema Registry](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/multiple-sr-hybrid) with hybrid configuration (onprem/confluent cloud)
  - [Confluent REST Proxy Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/rest-proxy-security-plugin) with Principal Propagation
  - [Confluent Schema Registry Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/schema-registry-security-plugin)
  - [Migrate Schemas to Confluent Cloud](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/migrate-schemas-to-confluent-cloud) using Confluent Replicator
  - [Confluent Cloud Networking](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/haproxy) using HAProxy
  - [Multiple Event Types in the Same Topic](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/multiple-event-types-in-topic)

## 🔄 Confluent Replicator and Mirror Maker 2

Using Multi-Data-Center setup with `US` 🇺🇸 and `EUROPE` 🇪🇺 clusters.

- <img src="https://github.com/vdesabou/kafka-docker-playground/raw/master/images/icons/using_confluent_replicator_as_connector.png" width="15"> [Using Confluent Replicator as connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/replicator/connect)
  - Using [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)
  - Using [SASL_PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-sasl-plain)
  - Using [Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-kerberos)
- 👾 [Using Confluent Replicator as executable](https://github.com/vdesabou/kafka-docker-playground/tree/master/replicator/executable)
  - Using [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)
  - Using [SASL_PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-sasl-plain)
  - Using [Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-kerberos)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> [Using Mirror Maker 2](https://github.com/vdesabou/kafka-docker-playground/tree/master/replicator/mirrormaker2)
  - Using [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)

## 🔐 Environments

Single cluster:

- [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext): no security
- [SASL_PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-plain): no SSL encryption, SASL/PLAIN authentication
- [SASL/SCRAM](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-scram) no SSL encryption, SASL/SCRAM-SHA-256 authentication
- [SASL_SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-ssl): SSL encryption, SASL/PLAIN authentication
- [2WAY_SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/2way-ssl): SSL encryption, SSL authentication
- [Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/kerberos): no SSL encryption, Kerberos GSSAPI authentication
- [SSL_Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ssl_kerberos) SSL encryption, Kerberos GSSAPI authentication
- [LDAP Authentication with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ldap-sasl-plain) no SSL encryption, SASL/PLAIN authentication using LDAP
- [LDAP Authorizer with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ldap-authorizer-sasl-plain) no SSL encryption, SASL/PLAIN authentication, LDAP Authorizer for ACL authorization
- [RBAC with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-sasl-plain) RBAC with no SSL encryption, SASL/PLAIN authentication

Multi-Data-Center setup:

- [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext): no security
- [SASL_PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-sasl-plain): no SSL encryption, SASL/PLAIN authentication
- [Kerberos](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-kerberos): no SSL encryption, Kerberos GSSAPI authentication

## Confluent Commercial

- Control Center
  - [Control Center in "Read-Only" mode](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-readonly-mode/)
  - [Configuring Control Center with LDAP authentication](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-ldap-auth)
- Tiered Storage
  - [Tiered storage with AWS S3](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/tiered-storage-with-aws)
  - [Tiered storage with Minio](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/tiered-storage-with-minio) (unsupported)
- [Confluent Rebalancer](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rebalancer)
- [JMS Client](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/jms-client)
- [RBAC with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-sasl-plain) RBAC with no SSL encryption, SASL/PLAIN authentication
- [Audit Logs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/audit-logs)
- [Confluent REST Proxy Security Plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rest-proxy-security-plugin) with SASL_SSL and 2WAY_SSL Principal Propagation
- [Cluster Linking](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/cluster-linking)
- [Testing RBAC with Azure AD](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-with-azure-ad)

## [CP-Ansible Playground](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/cp-ansible-playground)

Easily play with Confluent Platform Ansible playbooks by using Ubuntu based Docker images generated daily from this [cp-ansible-playground](https://github.com/vdesabou/cp-ansible-playground) repository

There is also a Confluent Cloud version available [here](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/cp-ansible-playground/)

## 👾 Other Playgrounds

- [Confluent Replicator](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-replicator) [also with [SASL_SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-replicator/README.md#with-sasl-ssl-authentication) and [2WAY_SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-replicator/README.md#with-ssl-authentication)]
- Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP source)](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/connect-override-policy-sftp-source)
- Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP sink)](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/connect-override-policy-sftp-sink)
- [How to write logs to files when using docker-compose](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/write-logs-to-files)
- [Publish logs to kafka with Elastic Filebeat](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/filebeat-to-kafka)
- <img src="https://www.pngitem.com/pimgs/m/33-335825_-net-core-logo-png-transparent-png.png" width="15"> [.NET](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-dotnet) basic producer
- <img src="https://kafka.js.org/img/kafkajs-logoV2.svg" width="15"> [KafkaJS](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-kafkajs) client (producer/consumer)
- <img src="https://datadog-docs.imgix.net/images/dd-docs-meta-image.png" width="15"> [Monitor Confluent Platform with Datadog](https://github.com/vdesabou/kafka-docker-playground/tools/datadog)
- Testing [KIP-108](https://cwiki.apache.org/confluence/display/KAFKA/KIP-108%3A+Create+Topic+Policy) [Create Topic Policy](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/create-topic-policy)

# 🎓 How to use

## 0️⃣ Prerequisites

You just need to have [docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/) installed on your machine !
Every command used in the playground is using Docker, this includes `jq` (except if you have it on your host already), `aws`, `az`, `gcloud`, etc..
The goal is to have a consistent behaviour and only depends on Docker.

## 🐳 Recommended Docker settings

![Diagram](https://github.com/vdesabou/kafka-docker-playground/blob/4c3e6d481fcff7353a64e666d09f0921153a70e1/ccloud/ccloud-demo/images/docker-settings.jpg?raw=true)

## 🌩 Running on AWS EC2 instance

If you want to run it on EC2 instance (highly recommended if you have low internet bandwith), you can use the AWS CloudFormation template provided [here]([cloudformation/README.md](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.json)).

For example, this is how I start it using aws CLI:

```bash
$ cp /path/to/kafka-docker-playground/cloudformation/kafka-docker-playground.json tmp.json
$ aws cloudformation create-stack  --stack-name kafka-docker-playground-$USER --template-body file://tmp.json --region eu-west-3
 --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME ParameterKey=InstanceName,ParameterValue=kafka-docker-playground-$USER
```

## <img src="https://gitpod.io/static/media/gitpod.2cdd910d.svg" width="15"> Running on Gitpod

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/vdesabou/kafka-docker-playground)
