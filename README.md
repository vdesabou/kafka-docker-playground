# kafka-docker-playground

Playground for Kafka/Confluent Docker experimentations

## 🔗 Connectors:

### ↘️ Source

* AWS
    * [S3](connect/connect-s3-source)
    * [Kinesis](connect/connect-kinesis-source)
    * [SQS](connect/connect-sqs-source)
        * using [SASL_SSL](connect/connect-sqs-source/README.md#with-sasl_ssl-authentication)
        * using [SSL](connect/connect-sqs-source/README.md#with-ssl-authentication)
    * [CloudWatch Logs](connect/connect-aws-cloudwatch-source)
* Debezium
    * using [MySQL](connect/connect-debezium-mysql-source)
    * using [PostgreSQL](connect/connect-debezium-postgresql-source)
    * using [MongoDB](connect/connect-debezium-mongodb-source)
    * using [SQL Server](connect/connect-debezium-sqlserver-source)
* [IBM MQ](connect/connect-ibm-mq-source)
* [Solace](connect/connect-solace-source)
* [ActiveMQ](connect/connect-active-mq-source)
* [TIBCO EMS](connect/connect-tibco-source)
* [Syslog](connect/connect-syslog-source)
* JDBC
    * using [MySQL](connect/connect-jdbc-mysql-source)
    * using [Oracle 11](connect/connect-jdbc-oracle11-source)
    * using [Oracle 12](connect/connect-jdbc-oracle12-source)
    * using [PostGreSQL](connect/connect-jdbc-postgresql-source)
    * using [SQL Server](connect/connect-jdbc-sqlserver-source)
* [MQTT](connect/connect-mqtt-source)
* [JMS TIBCO EMS](connect/connect-jms-tibco-source)
* [InfluxDB](connect/connect-influxdb-source)
* [Splunk](connect/connect-splunk-source)
* [HDFS 3](connect/connect-hdfs3-source)
* [RabbitMQ](connect/connect-rabbitmq-source)
* [Spool Dir](connect/connect-spool-dir-source)
* GCP
  * [Pub/Sub](connect/connect-gcp-pubsub-source)

### ↗️ Sink

* HDFS
    * [HDFS 2](connect/connect-hdfs-sink)
    * [HDFS 3](connect/connect-hdfs3-sink)
* AWS
    * [S3](connect/connect-s3-sink)
    * [Redshift](connect/connect-aws-redshift-sink)
    * [DynamoDB](connect/connect-aws-dynamodb-sink)
* [Elasticsearch](connect/connect-elasticsearch-sink)
* [HTTP](connect/connect-http-sink)
* GCP
    * [BigQuery](connect/connect-gcp-bigquery-sink)
    * [Cloud Functions](connect/connect-google-cloud-functions-sink)
    * [GCS](connect/connect-gcs-sink)
        * using [SASL_SSL](connect/connect-gcs-sink/README.md#with-sasl_ssl-authentication)
        * using [SSL](connect/connect-gcs-sink/README.md#with-ssl-authentication)
        * using [Kerberos GSSAPI](connect/connect-gcs-sink/README.md#with-kerberos-gssapi-authentication)
        * using [LDAP Authorizer SASL/PLAIN](connect/connect-gcs-sink/README.md#with-ldap-authorizer-with-saslplain)
* [Solace](connect/connect-solace-sink)
* [Splunk](connect/connect-splunk-sink)
* [TIBCO EMS](connect/connect-tibco-sink)
* [IBM MQ](connect/connect-ibm-mq-sink)
* [MQTT](connect/connect-mqtt-sink)
* [InfluxDB](connect/connect-influxdb-sink)
* [Cassandra](connect/connect-cassandra-sink)
* JDBC
    * using [MySQL](connect/connect-jdbc-mysql-sink)
    * using [Oracle 11](connect/connect-jdbc-oracle11-sink)
    * using [Oracle 12](connect/connect-jdbc-oracle12-sink)
    * using [PostGreSQL](connect/connect-jdbc-postgresql-sink)
    * using [SQL Server](connect/connect-jdbc-sqlserver-sink)
* [ActiveMQ](connect/connect-active-mq-sink)
* [OmniSci](connect/connect-omnisci-sink)
* JMS
    * using [ActiveMQ](connect/connect-jms-active-mq-sink)
    * using [Solace](connect/connect-jms-solace-sink)
    * using [TIBCO EMS](connect/connect-jms-tibco-sink)

## ☁️ Confluent Cloud:

* [Confluent Cloud Demo](ccloud/ccloud-demo)


## 🔐 Deployments

* [PLAINTEXT](environment/plaintext): no security
* [SASL_SSL](environment/sasl-ssl): SSL encryption / SASL_SSL or 2 way SSL authentication
* [Kerberos](environment/kerberos): no SSL encryption / Kerberos GSSAPI authentication
* [SSL_Kerberos](environment/ssl_kerberos) SSL encryption / Kerberos GSSAPI authentication
* [LDAP Authorizer with SASL/SCRAM-SHA-256](environment/ldap_authorizer_sasl_scram) no SSL encryption
* [LDAP Authorizer with SASL/PLAIN](environment/ldap_authorizer_sasl_plain) no SSL encryption

## Other:

* [Confluent Rebalancer](other/rebalancer)
* [Confluent Replicator](connect/connect-replicator) [also with [SASL_SSL](connect/connect-replicator/README.md#with-sasl_ssl-authentication)]

## 📚 Other useful resources

* [A Kafka Story 📖](https://github.com/framiere/a-kafka-story): A step by step guide to use Kafka ecosystem (Kafka Connect, KSQL, Java Consumers/Producers, etc..) with Docker
* [Kafka Boom Boom 💥](https://github.com/Dabz/kafka-boom-boom): An attempt to break kafka
* [Kafka Security playbook 🔒](https://github.com/Dabz/kafka-security-playbook): demonstrates various security configurations with Docker
* [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter): Multi-Data-Center setup using Confluent [Replicator](https://docs.confluent.io/current/connect/kafka-connect-replicator/index.html)
* [Kafka Platform Prometheus 📊](https://github.com/jeanlouisboudart/kafka-platform-prometheus): Simple demo of how to monitor Kafka Platform using Prometheus and Grafana.