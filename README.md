# kafka-docker-playground

Playground for Kafka/Confluent Docker experimentations

## 🔗 Connectors:

### ↘️ Source

* [AWS S3 Source](connect-s3-source/README.md)
* [AWS Kinesis Source](connect-kinesis-source/README.md)
* [AWS SQS Source](connect-sqs-source/README.md) [also with [SASL_SSL](connect-sqs-source/README.md#with-sasl_ssl-authentication) and [SSL](connect-sqs-source/README.md#with-ssl-authentication) authentications]
* [JDBC MySQL Source](connect-jdbc-source/README.md#MySQL)
* [Debezium MySQL source](connect-debezium-mysql-source/README)
* [Debezium PostgreSQL source](connect-debezium-postgresql-source/README.md)
* [Debezium MongoDB source](connect-debezium-mongodb-source/README.md)
* [IBM MQ Source](connect-ibm-mq-source/README.md)
* [Solace Source](connect-solace-source/README.md)
  
### ↗️ Sink

* [HDFS 2 Sink](connect-hdfs-sink/README.md)
* [AWS S3 Sink](connect-s3-sink/README.md)
* [Elasticsearch Sink](connect-elasticsearch-sink/README.md)
* [HTTP Sink](connect-http-sink/README.md)
* [GCP BigQuery Sink](connect-gcp-bigquery-sink/README.md)
* [GCS Sink](connect-gcs-sink/README.md) [also with [SASL_SSL](connect-gcs-sink/README.md#with-sasl_ssl-authentication), [SSL](connect-gcs-sink/README.md#with-ssl-authentication), [Kerberos GSSAPI](connect-gcs-sink/README.md#with-kerberos-gssapi-authentication) and [LDAP Authorizer SASL/PLAIN](connect-gcs-sink/README.md#with-ldap-authorizer-with-saslplain) authentications]  
* [Solace Sink](connect-solace-sink/README.md)
  
## ☁️ Confluent Cloud:

* [ccloud demo](ccloud-demo/README.md)


## 🔐 Deployments

* [PLAINTEXT](plaintext/README.md): no security
* [SASL_SSL](sasl-ssl/README.md): SSL encryption / SASL_SSL or 2 way SSL authentication
* [Kerberos](kerberos/README.md): no SSL encryption / Kerberos GSSAPI authentication
* [SSL_Kerberos](ssl_kerberos/README.md) SSL encryption / Kerberos GSSAPI authentication
* [LDAP Authorizer with SASL/SCRAM-SHA-256](ldap_authorizer_sasl_scram/README.md) no SSL encryption
* [LDAP Authorizer with SASL/PLAIN](ldap_authorizer_sasl_plain/README.md) no SSL encryption

## Other:

* [Confluent Rebalancer](rebalancer/README.md)

## 📚 Other useful resources

* [A Kafka Story](https://github.com/framiere/a-kafka-story): A step by step guide to use Kafka ecosystem (Kafka Connect, KSQL, Java Consumers/Producers, etc..) with Docker
* [Kafka Security playbook](https://github.com/Dabz/kafka-security-playbook): demonstrates various security configurations with Docker
* [MDC and single views](https://github.com/framiere/mdc-with-replicator-and-regexrouter): Multi-Data-Center setup using Confluent [Replicator](https://docs.confluent.io/current/connect/kafka-connect-replicator/index.html)
* [RBAC Demo](https://github.com/confluentinc/examples/blob/5.3.0-post/security/rbac/rbac-docker/README.md)