# kafka-docker-playground

Playground for Kafka/Confluent Docker experimentations

## 🔗 Connectors:

### ↘️ Source

* [AWS S3 Source](connect-s3-source)
* [AWS Kinesis Source](connect-kinesis-source)
* [AWS SQS Source](connect-sqs-source) [also with [SASL_SSL](connect-sqs-source/README.md#with-sasl_ssl-authentication) and [SSL](connect-sqs-source/README.md#with-ssl-authentication) authentications]
* [Debezium MySQL Source](connect-debezium-mysql-source/README)
* [Debezium PostgreSQL Source](connect-debezium-postgresql-source)
* [Debezium MongoDB Source](connect-debezium-mongodb-source)
* [IBM MQ Source](connect-ibm-mq-source)
* [Solace Source](connect-solace-source)
* [ActiveMQ Source](connect-active-mq-source)
* [TIBCO EMS Source](connect-tibco-source)
* [Syslog Source](connect-syslog-source)
* [JDBC MySQL Source](connect-jdbc-mysql-source)
* [JDBC Oracle 11 Source](connect-jdbc-oracle11-source)
* [JDBC Oracle 12 Source](connect-jdbc-oracle12-source)
* [MQTT Source](connect-mqtt-source)

### ↗️ Sink

* [HDFS 2 Sink](connect-hdfs-sink)
* [AWS S3 Sink](connect-s3-sink)
* [Elasticsearch Sink](connect-elasticsearch-sink)
* [HTTP Sink](connect-http-sink)
* [GCP BigQuery Sink](connect-gcp-bigquery-sink)
* [GCS Sink](connect-gcs-sink) [also with [SASL_SSL](connect-gcs-sink/README.md#with-sasl_ssl-authentication), [SSL](connect-gcs-sink/README.md#with-ssl-authentication), [Kerberos GSSAPI](connect-gcs-sink/README.md#with-kerberos-gssapi-authentication) and [LDAP Authorizer SASL/PLAIN](connect-gcs-sink/README.md#with-ldap-authorizer-with-saslplain) authentications]
* [Solace Sink](connect-solace-sink)
* [Splunk Sink](connect-splunk-sink)
* [TIBCO EMS Sink](connect-tibco-sink)
* [IBM MQ Sink](connect-ibm-mq-sink)
* [MQTT Sink](connect-mqtt-sink)


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