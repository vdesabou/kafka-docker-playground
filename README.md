# kafka-docker-playground

Playground for Kafka/Confluent Docker experimentations

## 🔗 Connectors:

### ↘️ Source

* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1200px-Amazon_Web_Services_Logo.svg.png" width="15"> AWS
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-s3.svg" width="15"> [S3](connect/connect-s3-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-kinesis.svg" width="15"> [Kinesis](connect/connect-kinesis-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-sqs.svg" width="15"> [SQS](connect/connect-sqs-source)
        * using [SASL_SSL](connect/connect-sqs-source/README.md#with-sasl_ssl-authentication)
        * using [SSL](connect/connect-sqs-source/README.md#with-ssl-authentication)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-cloudwatch.svg" width="15"> [CloudWatch Logs](connect/connect-aws-cloudwatch-source)
* <img src="https://avatars3.githubusercontent.com/u/11964329?s=400&v=4" width="15"> Debezium
    * using <img src="https://www.stickpng.com/assets/images/5848104fcef1014c0b5e4950.png" width="15"> [MySQL](connect/connect-debezium-mysql-source)
    * using <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostgreSQL](connect/connect-debezium-postgresql-source)
    * using <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-debezium-mongodb-source)
    * using <img src="https://myrealdomain.com/images/sql-server-logo-clipart-4.jpg" width="15"> [SQL Server](connect/connect-debezium-sqlserver-source)
* <img src="https://developer.ibm.com/messaging/wp-content/uploads/sites/18/2017/09/IBM-MQ-Sticker-300x260.png" width="15"> [IBM MQ](connect/connect-ibm-mq-source)
* <img src="https://pbs.twimg.com/profile_images/999017305869697024/eHwBaQtB_400x400.jpg" width="15"> [Solace](connect/connect-solace-source)
* <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-active-mq-source)
* <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-tibco-source)
* <img src="https://phelepjeremy.files.wordpress.com/2017/06/syslog-ng-logo.png?w=200" width="15"> [Syslog](connect/connect-syslog-source)
* <img src="https://opendistro.github.io/for-elasticsearch/assets/media/icons/javajdbc.png" width="15"> JDBC
    * using <img src="https://www.stickpng.com/assets/images/5848104fcef1014c0b5e4950.png" width="15"> [MySQL](connect/connect-jdbc-mysql-source)
    * using <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-source)
    * using <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-source)
    * using <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-source)
    * using <img src="https://myrealdomain.com/images/sql-server-logo-clipart-4.jpg" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-source)
* <img src="https://avatars1.githubusercontent.com/u/1544528?s=400&v=4" width="15"> [MQTT](connect/connect-mqtt-source)
* <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [JMS TIBCO EMS](connect/connect-jms-tibco-source)
* <img src="https://influxdata.github.io/branding/img/downloads/influxdata-logo--symbol--pool.svg" width="15"> [InfluxDB](connect/connect-influxdb-source)
* <img src="http://www.pharmajournalist.com/wp-content/uploads/2017/11/splunk-logo.jpg" width="15"> [Splunk](connect/connect-splunk-source)
* <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 3](connect/connect-hdfs3-source)
* <img src="https://cdn.worldvectorlogo.com/logos/rabbitmq.svg" width="15">  [RabbitMQ](connect/connect-rabbitmq-source)
* <img src="https://www.pngfind.com/pngs/m/66-661812_upload-file-icon-png-small-file-image-icon.png" width="15"> [Spool Dir](connect/connect-spool-dir-source)
* <img src="https://library.kissclipart.com/20181208/the/kissclipart-google-cloud-storage-clipart-google-cloud-platform-196ffd87fde25da8.jpg" width="15"> GCP
  * <img src="https://miro.medium.com/max/512/1*LXO5TpyB1GnCAE5-pz6L6Q.png" width="15"> [Pub/Sub](connect/connect-gcp-pubsub-source)
  * <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcs-source)
* <img src="https://www.stickpng.com/assets/images/5847f246cef1014c0b5e4865.png" width="15"> [Couchbase](connect/connect-couchbase-source)
* <img src="https://cdn.iconscout.com/icon/free/png-512/sftp-1758329-1496548.png" width="15"> [SFTP](connect/connect-sftp-source)

### ↗️ Sink

* <img src="https://banner2.cleanpng.com/20180811/ie/kisspng-apache-hadoop-logo-hadoop-distributed-file-system-big-data-weekly-quiz-getindata-5b6e73c46d0f95.0828181915339652524467.jpg" width="15"> Hadoop
    * <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 2](connect/connect-hdfs-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 3](connect/connect-hdfs3-sink)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1200px-Amazon_Web_Services_Logo.svg.png" width="15"> AWS
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-s3.svg" width="15"> [S3](connect/connect-s3-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [Redshift](connect/connect-aws-redshift-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-dynamodb.svg" width="15"> [DynamoDB](connect/connect-aws-dynamodb-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-lambda.svg" width="15"> [Lambda](connect/connect-aws-lambda-sink)
* <img src="https://www.logolynx.com/images/logolynx/20/2070b960b6b7a92c9821c07c4a9fca96.jpeg" width="15"> [Elasticsearch](connect/connect-elasticsearch-sink)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/HTTP_logo.svg/440px-HTTP_logo.svg.png" width="15"> [HTTP](connect/connect-http-sink)
* <img src="https://library.kissclipart.com/20181208/the/kissclipart-google-cloud-storage-clipart-google-cloud-platform-196ffd87fde25da8.jpg" width="15"> GCP
    * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/8/89/Google-BigQuery-Logo.svg/1200px-Google-BigQuery-Logo.svg.png" width="15"> [BigQuery](connect/connect-gcp-bigquery-sink)
    * <img src="https://img.stackshare.io/service/6672/google-cloud-functions.png" width="15"> [Cloud Functions](connect/connect-google-cloud-functions-sink)
    * <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcs-sink)
        * using [SASL_SSL](connect/connect-gcs-sink/README.md#with-sasl_ssl-authentication)
        * using [SSL](connect/connect-gcs-sink/README.md#with-ssl-authentication)
        * using [Kerberos GSSAPI](connect/connect-gcs-sink/README.md#with-kerberos-gssapi-authentication)
        * using [LDAP Authorizer SASL/PLAIN](connect/connect-gcs-sink/README.md#with-ldap-authorizer-with-saslplain)
* <img src="https://pbs.twimg.com/profile_images/999017305869697024/eHwBaQtB_400x400.jpg" width="15"> [Solace](connect/connect-solace-sink)
* <img src="http://www.pharmajournalist.com/wp-content/uploads/2017/11/splunk-logo.jpg" width="15"> [Splunk](connect/connect-splunk-sink)
* <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-tibco-sink)
* <img src="https://developer.ibm.com/messaging/wp-content/uploads/sites/18/2017/09/IBM-MQ-Sticker-300x260.png" width="15"> [IBM MQ](connect/connect-ibm-mq-sink)
* <img src="https://avatars1.githubusercontent.com/u/1544528?s=400&v=4" width="15"> [MQTT](connect/connect-mqtt-sink)
* <img src="https://influxdata.github.io/branding/img/downloads/influxdata-logo--symbol--pool.svg" width="15"> [InfluxDB](connect/connect-influxdb-sink)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Cassandra_logo.svg/1280px-Cassandra_logo.svg.png" width="15"> [Cassandra](connect/connect-cassandra-sink)
* <img src="https://opendistro.github.io/for-elasticsearch/assets/media/icons/javajdbc.png" width="15"> JDBC
    * using <img src="https://www.stickpng.com/assets/images/5848104fcef1014c0b5e4950.png" width="15"> [MySQL](connect/connect-jdbc-mysql-sink)
    * using <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-sink)
    * using <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-sink)
    * using <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-sink)
    * using <img src="https://myrealdomain.com/images/sql-server-logo-clipart-4.jpg" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-sink)
* <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-active-mq-sink)
* <img src="https://res-2.cloudinary.com/crunchbase-production/image/upload/c_lpad,h_256,w_256,f_auto,q_auto:eco/esdppsq3l6aqw0jdkpv3" width="15"> [OmniSci](connect/connect-omnisci-sink)
* <img src="http://logodesignfx.com/wp-content/uploads/2019/04/jms-logo-1.png" width="15"> JMS
    * using <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-jms-active-mq-sink)
    * using <img src="https://pbs.twimg.com/profile_images/999017305869697024/eHwBaQtB_400x400.jpg" width="15"> [Solace](connect/connect-jms-solace-sink)
    * using <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-jms-tibco-sink)
* <img src="https://carlisletheacarlisletheatre.org/images/azure-logo-transparent-3.png" width="15"> Azure
    * <img src="https://dellenny.com/wp-content/uploads/2019/04/azure-storage-blob.png" width="15"> [Blob Storage](connect/connect-azure-blob-storage-sink)
    * <img src="https://2.bp.blogspot.com/-491wbRLWQAQ/WXZVyGJ0kaI/AAAAAAAAE3g/Cedi8ujEAWYJjgWILvvke6lwqUtqg665gCLcBGAs/s1600/azuredatalake.png" width="15"> [Data Lake Gen1](connect/connect-azure-data-lake-storage-gen1-sink)
    * <img src="https://2.bp.blogspot.com/-491wbRLWQAQ/WXZVyGJ0kaI/AAAAAAAAE3g/Cedi8ujEAWYJjgWILvvke6lwqUtqg665gCLcBGAs/s1600/azuredatalake.png" width="15"> [Data Lake Gen2](connect/connect-azure-data-lake-storage-gen2-sink)
* <img src="https://go.neo4j.com/rs/710-RRC-335/images/neo4j_logo_globe.png" width="15"> [Neo4j](connect/connect-neo4j-sink)
* <img src="https://www.stickpng.com/assets/images/5847f246cef1014c0b5e4865.png" width="15"> [Couchbase](connect/connect-couchbase-sink)
* <img src="https://cdn.iconscout.com/icon/free/png-512/sftp-1758329-1496548.png" width="15"> [SFTP](connect/connect-sftp-sink)

## ☁️ Confluent Cloud:

* <img src="https://pbs.twimg.com/profile_images/979058850207641601/cLCehePZ.jpg" width="15"> [Confluent Cloud Demo](ccloud/ccloud-demo)

  * How to connect your components to Confluent Cloud
  * How to monitor your Confluent Cloud cluster
  * How to restrict access
  * etc...

![Diagram](./ccloud/ccloud-demo/images/diagram.png)


## 🔐 Deployments

* [PLAINTEXT](environment/plaintext): no security
* [SASL_PLAIN](environment/sasl-plain): no SSL encryption / SASL/PLAIN authentication
* [SASL_SSL](environment/sasl-ssl): SSL encryption / SASL_SSL or 2 way SSL authentication
* [Kerberos](environment/kerberos): no SSL encryption / Kerberos GSSAPI authentication
* [SSL_Kerberos](environment/ssl_kerberos) SSL encryption / Kerberos GSSAPI authentication
* [LDAP Authorizer with SASL/SCRAM-SHA-256](environment/ldap_authorizer_sasl_scram) no SSL encryption
* [LDAP Authorizer with SASL/PLAIN](environment/ldap_authorizer_sasl_plain) no SSL encryption

## 🎓 Kafka Tutorials

This is just the excellent examples in [Kafka tutorial](https://kafka-tutorials.confluent.io) but in Docker version for ease of use.

* <img src="https://kafka-tutorials.confluent.io/assets/img/icon-function.svg" width="15"> Apply a function to data
   * <img src="https://cdn.confluent.io/wp-content/uploads/ksq-lrocket.jpg" width="15"> KSQL
     * [Transform a stream of events](kafka-tutorials/ksql/transform-stream)
     * [Filter a stream of events](kafka-tutorials/ksql/filter-events)
     * [Rekey a stream with a value](kafka-tutorials/ksql/rekey-a-stream)
     * [Rekey a stream with a function](kafka-tutorials/ksql/rekey-with-function)
     * [Convert a stream's serialization format](kafka-tutorials/ksql/ksql-serialization)
     * [Split a stream of events into substreams](kafka-tutorials/ksql/split-stream)
     * [Merge many streams into one stream](kafka-tutorials/ksql/merge-streams)
  * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/440px-Apache_kafka.svg.png" width="15"> Kafka Streams
     * [Transform a stream of events](kafka-tutorials/ksql/transform-stream)
     * [Filter a stream of events](kafka-tutorials/kafka-streams/filter-events)
     * [Convert a stream's serialization format](kafka-tutorials/kafka-streams/ksql-serialization)
     * [Split a stream of events into substreams](kafka-tutorials/kafka-streams/split-stream)
     * [Merge many streams into one stream](kafka-tutorials/kafka-streams/merge-streams)
     * [Finding distinct events](kafka-tutorials/kafka-streams/distinct-events)
* <img src="https://kafka-tutorials.confluent.io/assets/img/icon-aggregate.svg" width="15"> Aggregate data
   * <img src="https://cdn.confluent.io/wp-content/uploads/ksq-lrocket.jpg" width="15"> KSQL
     * [Count a stream of events](kafka-tutorials/ksql/aggregate-count)
     * [Sum a stream of events](kafka-tutorials/ksql/aggregate-sum)
     * [Find the min/max in a stream of events](kafka-tutorials/ksql/aggregate-minmax)
  * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/440px-Apache_kafka.svg.png" width="15"> Kafka Streams
     * [Sum a stream of events](kafka-tutorials/kafka-streams/aggregate-sum)
* <img src="https://kafka-tutorials.confluent.io/assets/img/icon-join.svg" width="15"> Join data
   * <img src="https://cdn.confluent.io/wp-content/uploads/ksq-lrocket.jpg" width="15"> KSQL
     * [Join a stream and a table together](kafka-tutorials/ksql/join-stream-and-table)
     * [Join a stream and a stream together](kafka-tutorials/ksql/join-stream-and-stream)
     * [Join a table and a table together](kafka-tutorials/ksql/join-table-and-table)
  * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/440px-Apache_kafka.svg.png" width="15"> Kafka Streams
     * [Join a stream and a table together](kafka-tutorials/kafka-streams/join-stream-and-table)
* <img src="https://kafka-tutorials.confluent.io/assets/img/icon-time.svg" width="15"> Collect data over time
   * <img src="https://cdn.confluent.io/wp-content/uploads/ksq-lrocket.jpg" width="15"> KSQL
     * [Create tumbling windows](kafka-tutorials/ksql/tumbling-windows)
  * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/440px-Apache_kafka.svg.png" width="15"> Kafka Streams
     * [Create tumbling windows](kafka-tutorials/kafka-streams/tumbling-windows)



## Other:

* [Confluent Rebalancer](other/rebalancer)
* [Confluent Replicator](connect/connect-replicator) [also with [SASL_SSL](connect/connect-replicator/README.md#with-sasl_ssl-authentication)]`
* Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP source)](other/connect-override-policy-sftp-source)
* Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP sink)](other/connect-override-policy-sftp-sink)

## 📚 Other useful resources

* [A Kafka Story 📖](https://github.com/framiere/a-kafka-story): A step by step guide to use Kafka ecosystem (Kafka Connect, KSQL, Java Consumers/Producers, etc..) with Docker
* [Kafka Boom Boom 💥](https://github.com/Dabz/kafka-boom-boom): An attempt to break kafka
* [Kafka Security playbook 🔒](https://github.com/Dabz/kafka-security-playbook): demonstrates various security configurations with Docker
* [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter): Multi-Data-Center setup using Confluent [Replicator](https://docs.confluent.io/current/connect/kafka-connect-replicator/index.html)
* [Kafka Platform Prometheus 📊](https://github.com/jeanlouisboudart/kafka-platform-prometheus): Simple demo of how to monitor Kafka Platform using Prometheus and Grafana.