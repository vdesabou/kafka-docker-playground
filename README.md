# kafka-docker-playground

Playground for Kafka/Confluent Docker experimentations

## 🔗 Connectors:

### ↘️ Source

* [AWS S3](connect-s3-source)
* [AWS Kinesis](connect-kinesis-source)
* [AWS SQS](connect-sqs-source)
    * using [SASL_SSL](connect-sqs-source/README.md#with-sasl_ssl-authentication)
    * using [SSL](connect-sqs-source/README.md#with-ssl-authentication)
* [Debezium MySQL](connect-debezium-mysql-source/README)
* [Debezium PostgreSQL](connect-debezium-postgresql-source)
* [Debezium MongoDB](connect-debezium-mongodb-source)
* [IBM MQ](connect-ibm-mq-source)
* [Solace](connect-solace-source)
* [ActiveMQ](connect-active-mq-source)
* [TIBCO EMS](connect-tibco-source)
* [Syslog](connect-syslog-source)
* JDBC
    * using [MySQL](connect-jdbc-mysql-source)
    * using [Oracle 11](connect-jdbc-oracle11-source)
    * using [Oracle 12](connect-jdbc-oracle12-source)
    * using [PostGreSQL](connect-jdbc-postgresql-source)
* [MQTT](connect-mqtt-source)
* [JMS TIBCO](connect-jms-tibco-source)
* [InfluxDB](connect-influxdb-source)

### ↗️ Sink

* [HDFS 2](connect-hdfs-sink)
* [AWS S3](connect-s3-sink)
* [Elasticsearch](connect-elasticsearch-sink)
* [HTTP](connect-http-sink)
* [GCP BigQuery](connect-gcp-bigquery-sink)
* [GCS](connect-gcs-sink)
    * using [SASL_SSL](connect-gcs-sink/README.md#with-sasl_ssl-authentication)
    * using [SSL](connect-gcs-sink/README.md#with-ssl-authentication)
    * using [Kerberos GSSAPI](connect-gcs-sink/README.md#with-kerberos-gssapi-authentication)
    * using  [LDAP Authorizer SASL/PLAIN](connect-gcs-sink/README.md#with-ldap-authorizer-with-saslplain)
* [Solace](connect-solace-sink)
* [Splunk](connect-splunk-sink)
* [TIBCO EMS](connect-tibco-sink)
* [IBM MQ](connect-ibm-mq-sink)
* [MQTT](connect-mqtt-sink)
* [InfluxDB](connect-influxdb-sink)
* [Cassandra](connect-cassandra-sink)
* [Google Cloud Functions](connect-google-cloud-functions-sink)
* JDBC
    * using [MySQL](connect-jdbc-mysql-sink)
    * using [PostGreSQL](connect-jdbc-postgresql-sink)

## ☁️ Confluent Cloud:

* [ccloud demo](ccloud-demo)


## 🔐 Deployments

* [PLAINTEXT](plaintext): no security
* [SASL_SSL](sasl-ssl): SSL encryption / SASL_SSL or 2 way SSL authentication
* [Kerberos](kerberos): no SSL encryption / Kerberos GSSAPI authentication
* [SSL_Kerberos](ssl_kerberos) SSL encryption / Kerberos GSSAPI authentication
* [LDAP Authorizer with SASL/SCRAM-SHA-256](ldap_authorizer_sasl_scram) no SSL encryption
* [LDAP Authorizer with SASL/PLAIN](ldap_authorizer_sasl_plain) no SSL encryption

## Other:

* [Confluent Rebalancer](rebalancer)
* [Confluent Replicator](connect-replicator) [also with [SASL_SSL](connect-replicator/README.md#with-sasl_ssl-authentication)]

## 📚 Other useful resources

* [A Kafka Story 📖](https://github.com/framiere/a-kafka-story): A step by step guide to use Kafka ecosystem (Kafka Connect, KSQL, Java Consumers/Producers, etc..) with Docker
* [Kafka Boom Boom 💥](https://github.com/Dabz/kafka-boom-boom): An attempt to break kafka
* [Kafka Security playbook 🔒](https://github.com/Dabz/kafka-security-playbook): demonstrates various security configurations with Docker
* [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter): Multi-Data-Center setup using Confluent [Replicator](https://docs.confluent.io/current/connect/kafka-connect-replicator/index.html)
* [RBAC Demo 👥](https://github.com/confluentinc/examples/blob/5.3.0-post/security/rbac/rbac-docker)