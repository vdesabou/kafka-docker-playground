<!-- omit in toc -->
# <img src="https://www.docker.com/sites/default/files/d8/2019-07/vertical-logo-monochromatic.png" width="24"> <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="24"> kafka-docker-playground [![Build Status](https://travis-ci.com/vdesabou/kafka-docker-playground.svg?branch=master)](https://travis-ci.com/vdesabou/kafka-docker-playground)

Playground for Kafka/Confluent Docker experimentations...

ℹ️ [How to run](https://github.com/vdesabou/kafka-docker-playground/wiki/How-to-run)

<!-- omit in toc -->
## Table of Contents

- [🔗 Kafka Connectors](#-kafka-connectors)
  - [↘️ Source](#️-source)
  - [↗️ Sink](#️-sink)
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

### ↘️ Source

- <img src="./images/icons/hdfs_2.svg" width="15"> Hadoop
    - <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 2](connect/connect-hdfs2-source)
    - <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 3](connect/connect-hdfs3-source)
- <img src="./images/icons/aws.png" width="15"> AWS
    - <img src="./images/icons/s3.png" width="15"> [S3](connect/connect-aws-s3-source)
    - <img src="./images/icons/kinesis.svg" width="15"> [Kinesis](connect/connect-aws-kinesis-source)
    - <img src="./images/icons/sqs.svg" width="15"> [SQS](connect/connect-aws-sqs-source)
        - using [SASL_SSL](connect/connect-aws-sqs-source/README.md#with-sasl-ssl-authentication)
        - using [SSL](connect/connect-aws-sqs-source/README.md#with-ssl-authentication)
    - <img src="./images/icons/cloudwatch_logs.svg" width="15"> [CloudWatch Logs](connect/connect-aws-cloudwatch-logs-source)
    - <img src="./images/icons/aws_redshift.png" width="15"> [AWS Redshift](connect/connect-jdbc-aws-redshift-source) (using JDBC)
- <img src="./images/icons/debezium.png" width="15"> Debezium
    - <img src="./images/icons/mysql.jpg" width="15"> [MySQL](connect/connect-debezium-mysql-source)
    - <img src="./images/icons/postgresql.png" width="15"> [PostgreSQL](connect/connect-debezium-postgresql-source)
    - <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB](connect/connect-debezium-mongodb-source)
    - <img src="./images/icons/sql_server.png" width="15"> [SQL Server](connect/connect-debezium-sqlserver-source)
- <img src="./images/icons/ibm_mq.png" width="15"> [IBM MQ](connect/connect-ibm-mq-source)
- <img src="./images/icons/solace.jpg" width="15"> [Solace](connect/connect-solace-source)
- <img src="./images/icons/activemq.png" width="15"> [ActiveMQ](connect/connect-active-mq-source)
- <img src="./images/icons/tibco_ems.png" width="15"> [TIBCO EMS](connect/connect-tibco-source)
- <img src="./images/icons/syslog.png?w=200" width="15"> [Syslog](connect/connect-syslog-source)
- <img src="./images/icons/jdbc.png" width="15"> JDBC
    - <img src="./images/icons/mysql.jpg" width="15"> [MySQL](connect/connect-jdbc-mysql-source)
    - <img src="./images/icons/oracle_11.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-source)
    - <img src="./images/icons/oracle_11.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-source)
    - <img src="./images/icons/postgresql.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-source)
    - <img src="./images/icons/sql_server.png" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-source)
    - <img src="./images/icons/aws_redshift.png" width="15"> [AWS Redshift](connect/connect-jdbc-aws-redshift-source)
- <img src="./images/icons/mqtt.png" width="15"> [MQTT](connect/connect-mqtt-source)
- <img src="./images/icons/tibco_ems.png" width="15"> [JMS TIBCO EMS](connect/connect-jms-tibco-source)
- <img src="./images/icons/influxdb.svg" width="15"> [InfluxDB](connect/connect-influxdb-source)
- <img src="./images/icons/splunk.jpg" width="15"> [Splunk](connect/connect-splunk-source)
- <img src="./images/icons/rabbitmq.svg" width="15">  [RabbitMQ](connect/connect-rabbitmq-source)
- <img src="./images/icons/spool_dir.png" width="15"> [Spool Dir](connect/connect-spool-dir-source)
- <img src="https://cloud.google.com/images/social-icon-google-cloud-1200-630.png" width="15"> GCP
  - <img src="https://miro.medium.com/max/512/1*LXO5TpyB1GnCAE5-pz6L6Q.png" width="15"> [Pub/Sub](connect/connect-gcp-pubsub-source)
  - <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcp-gcs-source)
  - <img src="./images/icons/firebase.svg" width="15"> [Firebase](connect/connect-gcp-firebase-source)
- <img src="./images/icons/couchbase.svg" width="15"> [Couchbase](connect/connect-couchbase-source)
- <img src="./images/icons/sftp.png" width="15"> [SFTP](connect/connect-sftp-source)
- <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB](connect/connect-mongodb-source)
- <img src="./images/icons/kudu.png" width="15"> [Kudu](connect/connect-kudu-source)
- <img src="./images/icons/snmp_trap.png" width="15"> [SNMP Trap](connect/connect-snmp-source)
- <img src="./images/icons/servicenow.png" width="15"> [ServiceNow](connect/connect-servicenow-source)
- <img src="./images/icons/data_diode.jpg" width="15"> [Data Diode](connect/connect-datadiode-source-sink)
- <img src="./images/icons/azure.png" width="15"> Azure
    - <img src="./images/icons/blob_storage.png" width="15"> [Blob Storage](connect/connect-azure-blob-storage-source)
    - <img src="./images/icons/event_hubs.png" width="15"> [Event Hubs](connect/connect-azure-event-hubs-source)
    - <img src="./images/icons/service_bus.png" width="15"> [Service Bus](connect/connect-azure-service-bus-source)
- <img src="https://www.cleo.com/sites/default/files/2018-10/logo_ftps-mod-11%20%281%29.svg" height="15"> [FTPS](connect/connect-ftps-source)
- <img src="./images/icons/salesforce.png" width="15"> Salesforce
    - <img src="./images/icons/salesforce.png" height="15"> [PushTopics](connect/connect-salesforce-pushtopics-source)
    - <img src="./images/icons/salesforce.png" height="15"> [Bulk API](connect/connect-salesforce-bulkapi-source)
    - <img src="./images/icons/salesforce.png" height="15"> [CDC](connect/connect-salesforce-cdc-source)
    - <img src="./images/icons/salesforce.png" height="15"> [Platform Events](connect/connect-salesforce-platform-events-source)
- <img src="./images/icons/amps.png" width="15"> [AMPS](connect/connect-amps-source)
- <img src="./images/icons/jira.png" width="15"> [JIRA](connect/connect-jira-source)
- <img src="./images/icons/github.png" width="15"> [Github](connect/connect-github-source)

### ↗️ Sink

- <img src="./images/icons/hdfs_2.svg" width="15"> Hadoop
    - <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 2](connect/connect-hdfs2-sink)
    - <img src="./images/icons/hdfs_2.svg" width="15"> [HDFS 3](connect/connect-hdfs3-sink)
- <img src="./images/icons/aws.png" width="15"> AWS
    - <img src="./images/icons/s3.png" width="15"> [S3](connect/connect-aws-s3-sink)
    - <img src="./images/icons/aws_redshift.png" width="15"> [Redshift](connect/connect-aws-redshift-sink)
    - <img src="./images/icons/dynamodb.svg" width="15"> [DynamoDB](connect/connect-aws-dynamodb-sink)
    - <img src="./images/icons/lambda.svg" width="15"> [Lambda](connect/connect-aws-lambda-sink)
    - <img src="./images/icons/cloudwatch_logs.svg" width="15"> [CloudWatch Metrics](connect/connect-aws-cloudwatch-metrics-sink)
- <img src="./images/icons/elasticsearch.png" width="15"> [Elasticsearch](connect/connect-elasticsearch-sink)
- <img src="./images/icons/http.png" width="15"> [HTTP](connect/connect-http-sink)
- <img src="./images/icons/gcp.png" width="15"> GCP
    - <img src="./images/icons/bigquery.png" width="15"> [BigQuery](connect/connect-gcp-bigquery-sink)
    - <img src="./images/icons/cloud_functions.png" width="15"> [Cloud Functions](connect/connect-gcp-cloud-functions-sink)
    - <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcp-gcs-sink)
        - using [SASL_SSL](connect/connect-gcp-gcs-sink/README.md#with-sasl-ssl-authentication)
        - using [SSL](connect/connect-gcp-gcs-sink/README.md#with-ssl-authentication)
        - using [Kerberos GSSAPI](connect/connect-gcp-gcs-sink/README.md#with-kerberos-gssapi-authentication)
        - using [LDAP Authorizer SASL/PLAIN](connect/connect-gcp-gcs-sink/README.md#with-ldap-authorizer-with-saslplain)
        - using [RBAC environment SASL/PLAIN](connect/connect-gcp-gcs-sink/README.md#with-rbac-environment-with-saslplain)
    - <img src="./images/icons/firebase.svg" width="15"> [Firebase](connect/connect-gcp-firebase-sink)
    - <img src="./images/icons/spanner.png" width="15"> [Spanner](connect/connect-gcp-spanner-sink)
- <img src="./images/icons/solace.jpg" width="15"> [Solace](connect/connect-solace-sink)
- <img src="./images/icons/splunk.jpg" width="15"> [Splunk](connect/connect-splunk-sink)
- <img src="./images/icons/tibco_ems.png" width="15"> [TIBCO EMS](connect/connect-tibco-sink)
- <img src="./images/icons/ibm_mq.png" width="15"> [IBM MQ](connect/connect-ibm-mq-sink)
- <img src="./images/icons/mqtt.png" width="15"> [MQTT](connect/connect-mqtt-sink)
- <img src="./images/icons/influxdb.svg" width="15"> [InfluxDB](connect/connect-influxdb-sink)
- <img src="./images/icons/cassandra.png" width="15"> [Cassandra](connect/connect-cassandra-sink)
- <img src="./images/icons/jdbc.png" width="15"> JDBC
    - <img src="./images/icons/mysql.jpg" width="15"> [MySQL](connect/connect-jdbc-mysql-sink)
    - <img src="./images/icons/oracle_11.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-sink)
    - <img src="./images/icons/oracle_11.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-sink)
    - <img src="./images/icons/postgresql.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-sink)
    - <img src="./images/icons/sql_server.png" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-sink)
    - <img src="./images/icons/vertica.png" width="15"> [Vertica](connect/connect-jdbc-vertica-sink)
    - <img src="./images/icons/hive.png" width="15"> [Hive](connect/connect-jdbc-hive-sink)
- <img src="./images/icons/activemq.png" width="15"> [ActiveMQ](connect/connect-active-mq-sink)
- <img src="./images/icons/omnisci.png" width="15"> [OmniSci](connect/connect-omnisci-sink)
- <img src="./images/icons/jms.jpg" width="15"> JMS
    - <img src="./images/icons/activemq.png" width="15"> [ActiveMQ](connect/connect-jms-active-mq-sink)
    - <img src="./images/icons/solace.jpg" width="15"> [Solace](connect/connect-jms-solace-sink)
    - <img src="./images/icons/tibco_ems.png" width="15"> [TIBCO EMS](connect/connect-jms-tibco-sink)
- <img src="./images/icons/azure.png" width="15"> Azure
    - <img src="./images/icons/blob_storage.png" width="15"> [Blob Storage](connect/connect-azure-blob-storage-sink)
    - <img src="./images/icons/data_lake_gen1.png" width="15"> [Data Lake Gen1](connect/connect-azure-data-lake-storage-gen1-sink)
    - <img src="./images/icons/data_lake_gen1.png" width="15"> [Data Lake Gen2](connect/connect-azure-data-lake-storage-gen2-sink)
    - <img src="./images/icons/sql_data_warehouse.png" width="15"> [SQL Data Warehouse](connect/connect-azure-sql-data-warehouse-sink)
    - <img src="./images/icons/search.png" width="15"> [Search](connect/connect-azure-search-sink)
- <img src="./images/icons/neo4j.png" width="15"> [Neo4j](connect/connect-neo4j-sink)
- <img src="./images/icons/couchbase.svg" width="15"> [Couchbase](connect/connect-couchbase-sink)
- <img src="./images/icons/sftp.png" width="15"> [SFTP](connect/connect-sftp-sink)
- <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB](connect/connect-mongodb-sink)
- <img src="./images/icons/hbase.png" width="15"> [HBase](connect/connect-hbase-sink)
- <img src="./images/icons/redis.jpg" width="15"> [Redis](connect/connect-redis-sink)
- <img src="./images/icons/kudu.png" width="15"> [Kudu](connect/connect-kudu-sink)
- <img src="./images/icons/vertica.png" width="15"> [Vertica](connect/connect-vertica-sink)
- <img src="./images/icons/servicenow.png" width="15"> [ServiceNow](connect/connect-servicenow-sink)
- <img src="https://min.io/resources/img/logo/MINIO_Bird.png" height="15"> [Minio](connect/connect-minio-s3-sink)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/3/38/Prometheus_software_logo.svg/1200px-Prometheus_software_logo.svg.png" height="15">  [Prometheus](connect/connect-prometheus-sink)
- <img src="https://docs.snowflake.com/fr/_images/logo-snowflake-sans-text.png" height="15">  [Snowflake](connect/connect-snowflake-sink)
- <img src="https://static-dotconferences-com.s3.amazonaws.com/editionpartnerships/datadog.png" height="15"> [Datadog Metrics](connect/connect-datadog-metrics-sink)
- <img src="https://www.cleo.com/sites/default/files/2018-10/logo_ftps-mod-11%20%281%29.svg" height="15"> [FTPS](connect/connect-ftps-sink)
- <img src="./images/icons/rabbitmq.svg" width="15"> [RabbitMQ](connect/connect-rabbitmq-sink)
- <img src="./images/icons/salesforce.png" width="15"> Salesforce
    - <img src="./images/icons/salesforce.png" height="15"> [Bulk API](connect/connect-salesforce-bulkapi-sink)
    - <img src="./images/icons/salesforce.png" height="15"> [SObject](connect/connect-salesforce-sobject-sink)
    - <img src="./images/icons/salesforce.png" height="15"> [Platform Events](connect/connect-salesforce-platform-events-source)
- <img src="./images/icons/pagerduty.png" width="15"> [PagerDuty](connect/connect-pagerduty-sink)
- <img src="./images/icons/pivotal_gemfire.png" width="15"> [Pivotal Gemfire](connect/connect-pivotal-gemfire-sink)

## ☁️ Confluent Cloud

### [Confluent Cloud Demo](ccloud/ccloud-demo)

  - How to connect your components to Confluent Cloud
  - How to monitor your Confluent Cloud cluster
  - How to restrict access
  - etc...

![Diagram](./ccloud/ccloud-demo/images/diagram.png)

### 🔗 Kafka Connectors connected to Confluent Cloud

  - <img src="./images/icons/servicenow.png" width="15"> [ServiceNow](ccloud/connect-servicenow-source) source
  - <img src="./images/icons/servicenow.png" width="15"> [ServiceNow](ccloud/connect-servicenow-sink) sink
  - <img src="./images/icons/mongodb.jpg" width="15"> [MongoDB](ccloud/connect-debezium-mongodb-source) source
  - <img src="./images/icons/firebase.svg" width="15"> [Firebase](ccloud/connect-gcp-firebase-sink)

### Other

  - Using [cp-ansible](ccloud/cp-ansible-playground/) with Confluent Cloud
  - Demo using [dabz/ccloudexporter](https://github.com/Dabz/ccloudexporter) in order to pull [Metrics API](https://docs.confluent.io/current/cloud/metrics-api.html) data from Confluent Cloud cluster and export it to Prometheus (Grafana dashboard is also available)
  - <img src="https://www.pngitem.com/pimgs/m/33-335825_-net-core-logo-png-transparent-png.png" width="15"> [.NET](ccloud/client-dotnet) client (producer/consumer)
  - <img src="https://github.com/confluentinc/examples/raw/5.4.1-post/clients/cloud/images/go.png" width="15"> [Go](ccloud/client-go) client (producer/consumer)
  - <img src="https://vectorified.com/images/admin-icon-png-14.png" width="15"> [kafka-admin](ccloud/kafka-admin) Managing topics and ACLs using [matt-mangia/kafka-admin](https://github.com/matt-mangia/kafka-admin)
  - <img src="https://img.icons8.com/cotton/2x/synchronize--v1.png" width="15"> Confluent Replicator [OnPrem to cloud and Cloud to Cloud examples](ccloud/replicator)
  - <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="15"> [Multi-Cluster Schema Registry](ccloud/multiple-sr-hybrid) with hybrid configuration (onprem/confluent cloud)
  - [Confluent REST Proxy Security Plugin](ccloud/rest-proxy-security-plugin) with Principal Propagation
  - [Migrate Schemas to Confluent Cloud](ccloud/migrate-schemas-to-confluent-cloud) using Confluent Replicator

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
