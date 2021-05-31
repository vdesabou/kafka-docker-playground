<!-- omit in toc -->
# <img src="https://www.docker.com/sites/default/files/d8/2019-07/vertical-logo-monochromatic.png" width="24"> <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="24"> kafka-docker-playground ![CI](https://github.com/vdesabou/kafka-docker-playground/workflows/CI/badge.svg)

Playground for Kafka/Confluent Docker experimentations...

ℹ️ [How to run](https://github.com/vdesabou/kafka-docker-playground/wiki/How-to-run)

<!-- omit in toc -->
## Table of Contents

- [🔗 Kafka Connectors](#-kafka-connectors)
- [☁️ Confluent Cloud](#️-confluent-cloud)
  - [Confluent Cloud Demo](#confluent-cloud-demo)
  - [🔗 Kafka Connectors connected to Confluent Cloud](#-kafka-connectors-connected-to-confluent-cloud)
  - [Other](#other)
- [🔄 Confluent Replicator and Mirror Maker 2](#-confluent-replicator-and-mirror-maker-2)
- [🔐 Environments](#-environments)
- [Confluent Commercial](#confluent-commercial)
- [CP-Ansible Playground](#cp-ansible-playground)
- [👾 Other Playgrounds](#-other-playgrounds)
- [📚 Useful Resources](#-useful-resources)

## 🔗 Kafka Connectors

Quick start examples from Confluent [docs](https://docs.confluent.io/current/connect/managing/index.html) but in Docker version for ease of use.

| Connector  | Product Category  | Latest Version (*) | Type | Release Date| CP 6.1.1 [CI](https://github.com/vdesabou/kafka-docker-playground/actions?query=workflow%3ACI) latest results| CP 6.0.2 [CI](https://github.com/vdesabou/kafka-docker-playground/actions?query=workflow%3ACI) latest results| CP 5.5.3 [CI](https://github.com/vdesabou/kafka-docker-playground/actions?query=workflow%3ACI) latest results
|---|---|---|---|---|---|---|---|
| <img src="./images/icons/activemq.png" width="15"> [ActiveMQ Sink](connect/connect-active-mq-sink)  | Message Queue  | :connect/connect-active-mq-sink:
| <img src="./images/icons/activemq.png" width="15"> [ActiveMQ Source](connect/connect-active-mq-source)  | Message Queue  | :connect/connect-active-mq-source:
| <img src="./images/icons/cloudwatch_logs.svg" width="15"> [Amazon CloudWatch Logs Source](connect/connect-aws-cloudwatch-logs-source)  | Analytics  | :connect/connect-aws-cloudwatch-logs-source:
| <img src="./images/icons/cloudwatch_logs.svg" width="15"> [Amazon CloudWatch Metrics Sink](connect/connect-aws-cloudwatch-metrics-sink)  | Analytics  | :connect/connect-aws-cloudwatch-metrics-sink:
| <img src="./images/icons/dynamodb.svg" width="15"> [Amazon DynamoDB Sink](connect/connect-aws-dynamodb-sink) | Database  | :connect/connect-aws-dynamodb-sink:
| <img src="./images/icons/kinesis.svg" width="15"> [Amazon Kinesis Source](connect/connect-aws-kinesis-source) | Message Queue  | :connect/connect-aws-kinesis-source:
| <img src="./images/icons/aws_redshift.png" width="15"> [Amazon Redshift Sink](connect/connect-aws-redshift-sink) | Data Warehouse  | :confluentinc-kafka-connect-aws-redshift:
| <img src="./images/icons/aws_redshift.png" width="15"> [Amazon Redshift Source](connect/connect-jdbc-aws-redshift-source) (using JDBC) | Data Warehouse  | :connect/connect-jdbc-aws-redshift-source:
| <img src="./images/icons/s3.png" width="15"> [Amazon S3 Sink](connect/connect-aws-s3-sink) | Datastore  | :connect/connect-aws-s3-sink:
| <img src="./images/icons/s3.png" width="15"> [Amazon S3 Source](connect/connect-aws-s3-source)  | Datastore  | :connect/connect-aws-s3-source:
| <img src="./images/icons/sqs.svg" width="15"> [Amazon SQS Source](connect/connect-aws-sqs-source)  | Message Queue  | :connect/connect-aws-sqs-source:
| <img src="./images/icons/amps.png" width="15"> [AMPS Source](connect/connect-amps-source)  | Message Queue  | :connect/connect-amps-source:
| <img src="./images/icons/kudu.png" width="15"> [Apache Kudu Source](connect/connect-kudu-source)  | Database  | :connect/connect-kudu-source:
| <img src="./images/icons/kudu.png" width="15"> [Apache Kudu Sink](connect/connect-kudu-sink)  | Database  | :connect/connect-kudu-sink:
| <img src="./images/icons/lambda.svg" width="15"> [AWS Lambda Sink](connect/connect-aws-lambda-sink)  | SaaS Apps  | :connect/connect-aws-lambda-sink:
| <img src="./images/icons/blob_storage.png" width="15"> [Azure Blob Storage Sink](connect/connect-azure-blob-storage-sink)  | Datastore | :connect/connect-azure-blob-storage-sink:
| <img src="./images/icons/blob_storage.png" width="15"> [Azure Blob Storage Source](connect/connect-azure-blob-storage-source)  | Datastore | :connect/connect-azure-blob-storage-source:
| <img src="./images/icons/data_lake_gen1.png" width="15"> [Azure Data Lake Storage Gen1 Sink](connect/connect-azure-data-lake-storage-gen1-sink)  | Datastore | :connect/connect-azure-data-lake-storage-gen1-sink:
| <img src="./images/icons/data_lake_gen1.png" width="15"> [Azure Data Lake Storage Gen2 Sink](connect/connect-azure-data-lake-storage-gen2-sink)  | Datastore | :connect/connect-azure-data-lake-storage-gen2-sink:
| <img src="./images/icons/event_hubs.png" width="15"> [Azure Event Hubs Source](connect/connect-azure-event-hubs-source)  | Message Queue | :connect/connect-azure-event-hubs-source:
| <img src="./images/icons/azure_functions.png" width="15"> [Azure Functions Sink](connect/connect-azure-functions-sink) | SaaS Apps | :connect/connect-azure-functions-sink:
| <img src="./images/icons/search.png" width="15"> [Azure Search Sink](connect/connect-azure-search-sink)  | Analytics | :connect/connect-azure-search-sink:
| <img src="./images/icons/service_bus.png" width="15"> [Azure Service Bus Source](connect/connect-azure-service-bus-source)  | Message Queue | :connect/connect-azure-service-bus-source:
| <img src="./images/icons/sql_data_warehouse.png" width="15"> [Azure SQL Data Warehouse Sink](connect/connect-azure-sql-data-warehouse-sink)  | Data Warehouse | :connect/connect-azure-sql-data-warehouse-sink:
| <img src="./images/icons/cassandra.png" width="15"> [Cassandra Sink](connect/connect-cassandra-sink)  | Database | :connect/connect-cassandra-sink:
| <img src="./images/icons/couchbase.svg" width="15"> [Couchbase Sink](connect/connect-couchbase-sink)  | Database | :connect/connect-couchbase-sink:
| <img src="./images/icons/couchbase.svg" width="15"> [Couchbase Source](connect/connect-couchbase-source)  | Database | :connect/connect-couchbase-source:
| <img src="./images/icons/sql_server.png" width="15"> [Debezium CDC Microsoft SQL Server Source](connect/connect-debezium-sqlserver-source)  | CDC | :connect/connect-debezium-sqlserver-source:
| <img src="./images/icons/mysql.jpg" width="15"> [Debezium CDC MySQL Source](connect/connect-debezium-mysql-source)  | CDC | :connect/connect-debezium-mysql-source:
| <img src="./images/icons/postgresql.png" width="15"> [Debezium CDC PostgreSQL Source](connect/connect-debezium-postgresql-source)  | CDC | :connect/connect-debezium-postgresql-source:
| <img src="./images/icons/mongodb.jpg" width="15"> [Debezium CDC MongoDB Source](connect/connect-debezium-mongodb-source)  | CDC | :connect/connect-debezium-mongodb-source:
| <img src="./images/icons/data_diode.jpg" width="15"> [Data Diode Sink](connect/connect-datadiode-source-sink) | Logs | :connect/connect-datadiode-source-sink:
| <img src="./images/icons/data_diode.jpg" width="15"> [Data Diode Source](connect/connect-datadiode-source-sink) | Logs | :connect/connect-datadiode-source-sink:
| <img src="./images/icons/datadog.png" height="15"> [Datadog Metrics Sink](connect/connect-datadog-metrics-sink) | Analytics | :connect/connect-datadog-metrics-sink:
| <img src="./images/icons/elasticsearch.png" width="15"> [ElasticSearch Sink](connect/connect-elasticsearch-sink) | Analytics | :connect/connect-elasticsearch-sink:
| <img src="./images/icons/ftps.png" height="15"> [FTPS Sink](connect/connect-ftps-sink) | Datastore |:connect/connect-ftps-sink:
| <img src="./images/icons/ftps.png" height="15"> [FTPS Source](connect/connect-ftps-source) | Datastore |:connect/connect-ftps-source:
| <img src="./images/icons/pivotal_gemfire.png" width="15"> [Gemfire Sink](connect/connect-pivotal-gemfire-sink) | Database | :connect/connect-pivotal-gemfire-sink:
| <img src="./images/icons/github.png" width="15"> [Github Source](connect/connect-github-source) | SaaS Apps | :connect/connect-github-source:
| <img src="./images/icons/bigquery.png" width="15"> [Google BigQuery Sink](connect/connect-gcp-bigquery-sink) | Data Warehouse | :connect/connect-gcp-bigquery-sink:
| <img src="./images/icons/gcp_bigtable.png" width="15"> [Google Cloud BigTable Sink](connect/connect-gcp-bigtable-sink) | Database | :connect/connect-gcp-bigtable-sink:
| <img src="./images/icons/cloud_functions.png" width="15"> [Google Cloud Functions Sink](connect/connect-gcp-cloud-functions-sink) | SaaS Apps | :connect/connect-gcp-cloud-functions-sink:
| <img src="./images/icons/gcp_pubsub.png" width="15"> [Google Cloud Pub/Sub Source](connect/connect-gcp-pubsub-source) |  Message Queue | :connect/connect-gcp-pubsub-source:
| <img src="./images/icons/spanner.png" width="15"> [Google Cloud Spanner Sink](connect/connect-gcp-spanner-sink) |  Database | :connect/connect-gcp-spanner-sink:
| <img src="./images/icons/gcs.png" width="15"> [Google Cloud Storage Sink](connect/connect-gcp-gcs-sink) |  Datastore | :connect/connect-gcp-gcs-sink:
| <img src="./images/icons/gcs.png" width="15"> [Google Cloud Storage Source](connect/connect-gcp-gcs-source) |  Datastore | :connect/connect-gcp-gcs-source:
| <img src="./images/icons/firebase.svg" width="15"> [Google Firebase Realtime Database Sink](connect/connect-gcp-firebase-sink) |  Database | :connect/connect-gcp-firebase-sink:
| <img src="./images/icons/firebase.svg" width="15"> [Google Firebase Realtime Database Source](connect/connect-gcp-firebase-source) |  Database | :connect/connect-gcp-firebase-source:
| <img src="./images/icons/hbase.png" width="15"> [HBase Sink](connect/connect-hbase-sink) |  Database | :connect/connect-hbase-sink:
| <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 2 Source](connect/connect-hdfs2-source) |  Datastore | :connect/connect-hdfs2-source:
| <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 3 Source](connect/connect-hdfs3-source) |  Datastore | :connect/connect-hdfs3-source:
| <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 2 Sink](connect/connect-hdfs2-sink) |  Datastore | :connect/connect-hdfs2-sink:
| <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 3 Sink](connect/connect-hdfs3-sink) |  Datastore | :connect/connect-hdfs3-sink:
| <img src="./images/icons/http.png" width="15"> [HTTP Sink](connect/connect-http-sink) |  SaaS Apps | :connect/connect-http-sink:
| <img src="./images/icons/ibm_mq.png" width="15"> [IBM MQ Sink](connect/connect-ibm-mq-sink) |  Message Queue | :connect/connect-ibm-mq-sink:
| <img src="./images/icons/ibm_mq.png" width="15"> [IBM MQ Source](connect/connect-ibm-mq-source) |  Message Queue | :connect/connect-ibm-mq-source:
| <img src="./images/icons/influxdb.svg" width="15"> [InfluxDB Sink](connect/connect-influxdb-sink) |  Database | :connect/connect-influxdb-sink:
| <img src="./images/icons/influxdb.svg" width="15"> [InfluxDB Source](connect/connect-influxdb-source) |  Database | :connect/connect-influxdb-source:
| <img src="./images/icons/hive.png" width="15"> [JDBC Hive Sink](connect/connect-jdbc-hive-sink) |  Database | :connect/connect-jdbc-hive-sink:
| <img src="./images/icons/mysql.jpg" width="15"> [JDBC MySQL Sink](connect/connect-jdbc-mysql-sink) (also with 🔑 SSL and mTLS) |  Database | :connect/connect-jdbc-mysql-sink:
| <img src="./images/icons/oracle_11.jpg" width="15"> [JDBC Oracle 11 Sink](connect/connect-jdbc-oracle11-sink) |  Database | :connect/connect-jdbc-oracle11-sink:
| <img src="./images/icons/oracle_12.jpg" width="15"> [JDBC Oracle 12 Sink](connect/connect-jdbc-oracle12-sink) (also with 🔑 SSL and mTLS) |  Database | :connect/connect-jdbc-oracle12-sink:
| <img src="./images/icons/postgresql.png" width="15"> [JDBC PostGreSQL Sink](connect/connect-jdbc-postgresql-sink) |  Database | :connect/connect-jdbc-postgresql-sink:
| <img src="./images/icons/sql_server.png" width="15"> [JDBC Microsoft SQL Server Sink](connect/connect-jdbc-sqlserver-sink) |  Database | :connect/connect-jdbc-sqlserver-sink:
| <img src="./images/icons/vertica.png" width="15"> [JDBC Vertica Sink](connect/connect-jdbc-vertica-sink) |  Database | :connect/connect-jdbc-vertica-sink:
| <img src="./images/icons/mysql.jpg" width="15"> [JDBC MySQL Source](connect/connect-jdbc-mysql-source) (also with 🔑 SSL and mTLS) |  Database | :connect/connect-jdbc-mysql-source:
| <img src="./images/icons/oracle_11.jpg" width="15"> [JDBC Oracle 11 Source](connect/connect-jdbc-oracle11-source) |  Database | :connect/connect-jdbc-oracle11-source:
| <img src="./images/icons/oracle_12.jpg" width="15"> [JDBC Oracle 12 Source](connect/connect-jdbc-oracle12-source) (also with 🔑 SSL and mTLS) |  Database | :connect/connect-jdbc-oracle12-source:
| <img src="./images/icons/postgresql.png" width="15"> [JDBC PostGreSQL Source](connect/connect-jdbc-postgresql-source) |  Database | :connect/connect-jdbc-postgresql-source:
| <img src="./images/icons/sql_server.png" width="15"> [JDBC Microsoft SQL Server Source](connect/connect-jdbc-sqlserver-source) |  Database | :connect/connect-jdbc-sqlserver-source:
| <img src="./images/icons/jira.png" width="15"> [JIRA Source](connect/connect-jira-source) |  SaaS Apps | :connect/connect-jira-source:
| <img src="./images/icons/activemq.png" width="15"> [JMS ActiveMQ Sink](connect/connect-jms-active-mq-sink) |  Message Queue | :connect/connect-jms-active-mq-sink:
| <img src="./images/icons/solace.jpg" width="15"> [JMS Solace Sink](connect/connect-jms-solace-sink) |  Message Queue | :connect/connect-jms-solace-sink:
| <img src="./images/icons/tibco_ems.png" width="15"> [JMS TIBCO EMS Sink](connect/connect-jms-tibco-sink) |  Message Queue | :connect/connect-jms-tibco-sink:
| <img src="./images/icons/tibco_ems.png" width="15"> [JMS TIBCO EMS Source](connect/connect-jms-tibco-source) |  Message Queue | :connect/connect-jms-tibco-source:
| <img src="./images/icons/mapr.png" height="15"> [Mapr Sink](connect/connect-mapr-sink) |  Datastore | :confluentinc-kafka-connect-maprdb:
| <img src="./images/icons/marketo.png" height="15"> [Marketo Source](connect/connect-marketo-source) |  SaaS Apps | :connect/connect-marketo-source:
| <img src="./images/icons/minio.png" height="15"> [Minio Sink](connect/connect-minio-s3-sink) |  Datastore | :connect/connect-minio-s3-sink:
| <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB Sink](connect/connect-mongodb-sink) |  Database | :connect/connect-mongodb-sink:
| <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB Source](connect/connect-mongodb-source) |  Database | :connect/connect-mongodb-source:
| <img src="./images/icons/mqtt.png" width="15"> [MQTT Sink](connect/connect-mqtt-sink) |  IoT | :connect/connect-mqtt-sink:
| <img src="./images/icons/mqtt.png" width="15"> [MQTT Source](connect/connect-mqtt-source) |  IoT | :connect/connect-mqtt-source:
| <img src="./images/icons/neo4j.png" width="15"> [Neo4j Sink](connect/connect-neo4j-sink) |  Database | :connect/connect-neo4j-sink:
| <img src="./images/icons/omnisci.png" width="15"> [OmniSci Sink](connect/connect-omnisci-sink) |  Database | :connect/connect-omnisci-sink:
| <img src="./images/icons/oracle_12.jpg" width="15"> [Oracle CDC](connect/connect-cdc-oracle12-source) (also with 🔑 SSL and mTLS) |  Database | :connect/connect-cdc-oracle12-source:
| <img src="./images/icons/pagerduty.png" width="15"> [PagerDuty Sink](connect/connect-pagerduty-sink) |  SaaS Apps | :connect/connect-pagerduty-sink:
| <img src="./images/icons/prometheus.png" height="15">  [Prometheus Sink](connect/connect-prometheus-sink) |  Analytics | :connect/connect-prometheus-sink:
| <img src="./images/icons/rabbitmq.svg" width="15"> [RabbitMQ Sink](connect/connect-rabbitmq-sink) |  Message Queue | :connect/connect-rabbitmq-sink:
| <img src="./images/icons/rabbitmq.svg" width="15">  [RabbitMQ Source](connect/connect-rabbitmq-source) |  Message Queue | :connect/connect-rabbitmq-source:
| <img src="./images/icons/redis.jpg" width="15"> [Redis Sink](connect/connect-redis-sink) |  Database | :connect/connect-redis-sink:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce Bulk API Sink](connect/connect-salesforce-bulkapi-sink) |  SaaS Apps | :connect/connect-salesforce-bulkapi-sink:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce Bulk API Source](connect/connect-salesforce-bulkapi-source) |  SaaS Apps | :connect/connect-salesforce-bulkapi-source:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce CDC Source](connect/connect-salesforce-cdc-source) |  SaaS Apps | :connect/connect-salesforce-cdc-source:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce Platform Events Sink](connect/connect-salesforce-platform-events-sink) |  SaaS Apps | :connect/connect-salesforce-platform-events-sink:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce Platform Events Source](connect/connect-salesforce-platform-events-source) |  SaaS Apps | :connect/connect-salesforce-platform-events-source:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce PushTopics Source](connect/connect-salesforce-pushtopics-source) |  SaaS Apps | :connect/connect-salesforce-pushtopics-source:
| <img src="./images/icons/salesforce.png" height="15"> [SalesForce SObject Sink](connect/connect-salesforce-sobject-sink) |  SaaS Apps | :connect/connect-salesforce-sobject-sink:
| <img src="./images/icons/servicenow.png" width="15"> [ServiceNow Sink](connect/connect-servicenow-sink) |  SaaS Apps | :confluentinc-kafka-connect-servicenow:
| <img src="./images/icons/servicenow.png" width="15"> [ServiceNow Source](connect/connect-servicenow-source) |  SaaS Apps | :confluentinc-kafka-connect-servicenow:
| <img src="./images/icons/sftp.png" width="15"> [SFTP Sink](connect/connect-sftp-sink) |  Datastore | :connect/connect-sftp-sink:
| <img src="./images/icons/sftp.png" width="15"> [SFTP Source](connect/connect-sftp-source) |  Datastore | :connect/connect-sftp-source:
| <img src="./images/icons/snmp_trap.png" width="15"> [SNMP Trap Source](connect/connect-snmp-source) |  IoT | :connect/connect-snmp-source:
| <img src="./images/icons/snowflake.png" height="15">  [Snowflake Sink](connect/connect-snowflake-sink) |  Data Warehouse | :connect/connect-snowflake-sink:
| <img src="./images/icons/solace.jpg" width="15"> [Solace Sink](connect/connect-solace-sink) |  Message Queue | :connect/connect-solace-sink:
| <img src="./images/icons/solace.jpg" width="15"> [Solace Source](connect/connect-solace-source) |  Message Queue | :connect/connect-solace-source:
| <img src="./images/icons/splunk.jpg" width="15"> [Splunk Sink](connect/connect-splunk-sink) |  Analytics | :connect/connect-splunk-sink:
| <img src="./images/icons/splunk.jpg" width="15"> [Splunk Source](connect/connect-splunk-source) |  Analytics | :connect/connect-splunk-source:
| <img src="./images/icons/spool_dir.png" width="15"> [Spool Dir Source](connect/connect-spool-dir-source) |  Datastore | :connect/connect-spool-dir-source:
| <img src="./images/icons/syslog.png" width="15"> [Syslog Source](connect/connect-syslog-source) |  Logs | :connect/connect-syslog-source:
| <img src="./images/icons/tibco_ems.png" width="15"> [TIBCO EMS Sink](connect/connect-tibco-sink) |  Message Queue | :connect/connect-tibco-sink:
| <img src="./images/icons/tibco_ems.png" width="15"> [TIBCO EMS Source](connect/connect-tibco-source) |  Message Queue | :connect/connect-tibco-source:
| <img src="./images/icons/vertica.png" width="15"> [Vertica Sink](connect/connect-vertica-sink) |  Database | :connect/connect-vertica-sink:
| <img src="./images/icons/zendesk.png" width="15"> [Zendesk Source](connect/connect-zendesk-source) |  SaaS Apps | :connect/connect-zendesk-source:

\* You can change default connector version by setting `CONNECTOR_TAG` environment variable before starting a test, get more details [here](https://github.com/vdesabou/kafka-docker-playground/wiki/How-to-run#default-connector-version)

## ☁️ Confluent Cloud

### [Confluent Cloud Demo](ccloud/ccloud-demo)

  - How to connect your components to Confluent Cloud
  - How to monitor your Confluent Cloud cluster
  - How to restrict access
  - etc...

![Diagram](./ccloud/ccloud-demo/images/diagram.png)

### 🔗 Kafka Connectors connected to Confluent Cloud

  - <img src="./images/icons/kinesis.svg" width="15"> [AWS Kinesis](ccloud/connect-aws-kinesis-source) source
  - <img src="./images/icons/servicenow.png" width="15"> [ServiceNow](ccloud/connect-servicenow-source) source
  - <img src="./images/icons/servicenow.png" width="15"> [ServiceNow](ccloud/connect-servicenow-sink) sink
  - <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB](ccloud/connect-debezium-mongodb-source) source
  - <img src="./images/icons/firebase.svg" width="15"> [Firebase](ccloud/connect-gcp-firebase-sink)

### Other

  - Using [cp-ansible](ccloud/cp-ansible-playground/) with Confluent Cloud
  - Using [cp-helm-charts](ccloud/cp-helm-chart/) with Confluent Cloud
  - Using [confluent operator](ccloud/operator/) with Confluent Cloud
  - Demo using [dabz/ccloudexporter](https://github.com/Dabz/ccloudexporter) in order to pull [Metrics API](https://docs.confluent.io/current/cloud/metrics-api.html) data from Confluent Cloud cluster and export it to Prometheus (Grafana dashboard is also available)
  - <img src="https://www.pngitem.com/pimgs/m/33-335825_-net-core-logo-png-transparent-png.png" width="15"> [.NET](ccloud/client-dotnet) client (producer/consumer)
  - <img src="https://github.com/confluentinc/examples/raw/5.4.1-post/clients/cloud/images/go.png" width="15"> [Go](ccloud/client-go) client (producer/consumer)
  - <img src="https://vectorified.com/images/admin-icon-png-14.png" width="15"> [kafka-admin](ccloud/kafka-admin) Managing topics and ACLs using [matt-mangia/kafka-admin](https://github.com/matt-mangia/kafka-admin)
  - <img src="https://img.icons8.com/cotton/2x/synchronize--v1.png" width="15"> Confluent Replicator [OnPrem to cloud and Cloud to Cloud examples](ccloud/replicator)
  - <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="15"> [Multi-Cluster Schema Registry](ccloud/multiple-sr-hybrid) with hybrid configuration (onprem/confluent cloud)
  - [Confluent REST Proxy Security Plugin](ccloud/rest-proxy-security-plugin) with Principal Propagation
  - [Confluent Schema Registry Security Plugin](ccloud/schema-registry-security-plugin)
  - [Migrate Schemas to Confluent Cloud](ccloud/migrate-schemas-to-confluent-cloud) using Confluent Replicator
  - [Confluent Cloud Networking](ccloud/haproxy) using HAProxy

## 🔄 Confluent Replicator and Mirror Maker 2

Using Multi-Data-Center setup with `US` 🇺🇸 and `EUROPE` 🇪🇺 clusters.

- <img src="./images/icons/using_confluent_replicator_as_connector.png" width="15"> [Using Confluent Replicator as connector](replicator/connect)
  - Using [PLAINTEXT](environment/mdc-plaintext)
  - Using [SASL_PLAIN](environment/mdc-sasl-plain)
  - Using [Kerberos](environment/mdc-kerberos)
- 👾 [Using Confluent Replicator as executable](replicator/executable)
  - Using [PLAINTEXT](environment/mdc-plaintext)
  - Using [SASL_PLAIN](environment/mdc-sasl-plain)
  - Using [Kerberos](environment/mdc-kerberos)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> [Using Mirror Maker 2](replicator/mirrormaker2)
  - Using [PLAINTEXT](environment/mdc-plaintext)

## 🔐 Environments

Single cluster:

- [PLAINTEXT](environment/plaintext): no security
- [SASL_PLAIN](environment/sasl-plain): no SSL encryption, SASL/PLAIN authentication
- [SASL/SCRAM](environment/sasl-scram) no SSL encryption, SASL/SCRAM-SHA-256 authentication
- [SASL_SSL](environment/sasl-ssl): SSL encryption, SASL/PLAIN authentication
- [2WAY_SSL](environment/2way-ssl): SSL encryption, SSL authentication
- [Kerberos](environment/kerberos): no SSL encryption, Kerberos GSSAPI authentication
- [SSL_Kerberos](environment/ssl_kerberos) SSL encryption, Kerberos GSSAPI authentication
- [LDAP Authorizer with SASL/PLAIN](environment/ldap_authorizer_sasl_plain) no SSL encryption, SASL/PLAIN authentication, LDAP Authorizer for ACL authorization
- [RBAC with SASL/PLAIN](environment/rbac-sasl-plain) RBAC with no SSL encryption, SASL/PLAIN authentication

Multi-Data-Center setup:

- [PLAINTEXT](environment/mdc-plaintext): no security
- [SASL_PLAIN](environment/mdc-sasl-plain): no SSL encryption, SASL/PLAIN authentication
- [Kerberos](environment/mdc-kerberos): no SSL encryption, Kerberos GSSAPI authentication


## Confluent Commercial

- Control Center
  - [Control Center in "Read-Only" mode](other/control-center-readonly-mode/)
  - [Configuring Control Center with LDAP authentication](other/control-center-ldap-auth)
- Tiered Storage
  - [Tiered storage with AWS S3](other/tiered-storage-with-aws)
  - [Tiered storage with Minio](other/tiered-storage-with-minio) (unsupported)
- [Confluent Rebalancer](other/rebalancer)
- [JMS Client](other/jms-client)
- [RBAC with SASL/PLAIN](environment/rbac-sasl-plain) RBAC with no SSL encryption, SASL/PLAIN authentication
- [Audit Logs](other/audit-logs)
- [Confluent REST Proxy Security Plugin](other/rest-proxy-security-plugin) with SASL_SSL and 2WAY_SSL Principal Propagation

## [CP-Ansible Playground](other/cp-ansible-playground)

Easily play with Confluent Platform Ansible playbooks by using Ubuntu based Docker images generated daily from this [cp-ansible-playground](https://github.com/vdesabou/cp-ansible-playground) repository

There is also a Confluent Cloud version available [here](ccloud/cp-ansible-playground/)

## 👾 Other Playgrounds

- [Confluent Replicator](connect/connect-replicator) [also with [SASL_SSL](connect/connect-replicator/README.md#with-sasl-ssl-authentication) and [2WAY_SSL](connect/connect-replicator/README.md#with-ssl-authentication)]
- Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP source)](other/connect-override-policy-sftp-source)
- Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP sink)](other/connect-override-policy-sftp-sink)
- [How to write logs to files when using docker-compose](other/write-logs-to-files)
- [Publish logs to kafka with Elastic Filebeat](other/filebeat-to-kafka)
- <img src="https://www.pngitem.com/pimgs/m/33-335825_-net-core-logo-png-transparent-png.png" width="15"> [.NET](other/client-dotnet) basic producer
- <img src="https://datadog-docs.imgix.net/images/dd-docs-meta-image.png" width="15"> [Monitor Confluent Platform with Datadog](tools/datadog)

## 📚 Useful Resources

- [A Kafka Story 📖](https://github.com/framiere/a-kafka-story): A step by step guide to use Kafka ecosystem (Kafka Connect, KSQL, Java Consumers/Producers, etc..) with Docker
- [Kafka Boom Boom 💥](https://github.com/Dabz/kafka-boom-boom): An attempt to break kafka
- [Kafka Security playbook 🔒](https://github.com/Dabz/kafka-security-playbook): demonstrates various security configurations with Docker
- [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter): Multi-Data-Center setup using Confluent [Replicator](https://docs.confluent.io/current/connect/kafka-connect-replicator/index.html)
- [Kafka Platform Prometheus 📊](https://github.com/jeanlouisboudart/kafka-platform-prometheus): Simple demo of how to monitor Kafka Platform using Prometheus and Grafana.
