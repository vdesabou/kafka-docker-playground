<!-- omit in toc -->
# <img src="https://www.docker.com/sites/default/files/d8/2019-07/vertical-logo-monochromatic.png" width="24"> <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> <img src="https://res.cloudinary.com/dcvaxfika/image/upload/v1543961808/6.png" width="24"> kafka-docker-playground [![Build Status](https://travis-ci.com/vdesabou/kafka-docker-playground.svg?branch=master)](https://travis-ci.com/vdesabou/kafka-docker-playground)

Playground for Kafka/Confluent Docker experimentations...


----

ℹ️ By default Confluent Platform version 5.4.0 is used, but you can test with another version (greater or equal to 5.0.0) simply by exporting `TAG` environment variable:

Example:

```bash
export TAG=5.3.2
```

----

<!-- omit in toc -->
## Table of Contents
- [🔗 Kafka Connectors](#-kafka-connectors)
  - [↘️ Source](#️-source)
  - [↗️ Sink](#️-sink)
- [☁️ Confluent Cloud](#️-confluent-cloud)
  - [<img src="https://pbs.twimg.com/profile_images/979058850207641601/cLCehePZ.jpg" width="15"> Confluent Cloud Demo](#img-srchttpspbstwimgcomprofile_images979058850207641601clcehepzjpg-width15-confluent-cloud-demo)
  - [🔗 Kafka Connectors connected to Confluent Cloud](#-kafka-connectors-connected-to-confluent-cloud)
- [🔄 Confluent Replicator](#-confluent-replicator)
- [🔐 Environments](#-environments)
- [🎓 Kafka Tutorials](#-kafka-tutorials)
- [Confluent Commercial](#confluent-commercial)
- [👾 Other Playgrounds](#-other-playgrounds)
- [📚 Useful Resources](#-useful-resources)


## 🔗 Kafka Connectors

Quick start examples from Confluent [docs](https://docs.confluent.io/current/connect/managing/index.html) but in Docker version for ease of use.

### ↘️ Source

* <img src="https://mpng.pngfly.com/20190128/xso/kisspng-apache-hadoop-big-data-computer-software-data-scie-hadoop-and-tyrone-5c4f4554d98c79.8384600315486989648911.jpg" width="15"> Hadoop
    * <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 2](connect/connect-hdfs2-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 3](connect/connect-hdfs3-source)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1200px-Amazon_Web_Services_Logo.svg.png" width="15"> AWS
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-s3.svg" width="15"> [S3](connect/connect-aws-s3-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-kinesis.svg" width="15"> [Kinesis](connect/connect-aws-kinesis-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-sqs.svg" width="15"> [SQS](connect/connect-aws-sqs-source)
        * using [SASL_SSL](connect/connect-aws-sqs-source/README.md#with-sasl-ssl-authentication)
        * using [SSL](connect/connect-aws-sqs-source/README.md#with-ssl-authentication)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-cloudwatch.svg" width="15"> [CloudWatch Logs](connect/connect-aws-cloudwatch-logs-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [AWS Redshift](connect/connect-jdbc-aws-redshift-source) (using JDBC)
* <img src="https://avatars3.githubusercontent.com/u/11964329?s=400&v=4" width="15"> Debezium
    * <img src="https://banner2.cleanpng.com/20180803/abq/kisspng-mysql-cluster-database-management-system-专-题-咖-啡-与-代-码-5b640d8b2a2e53.6067051415332837231728.jpg" width="15"> [MySQL](connect/connect-debezium-mysql-source)
    * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostgreSQL](connect/connect-debezium-postgresql-source)
    * <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-debezium-mongodb-source)
    * <img src="https://www.netclipart.com/pp/m/39-396469_sql-server-logo-png.png" width="15"> [SQL Server](connect/connect-debezium-sqlserver-source)
* <img src="https://developer.ibm.com/messaging/wp-content/uploads/sites/18/2017/09/IBM-MQ-Sticker-300x260.png" width="15"> [IBM MQ](connect/connect-ibm-mq-source)
* <img src="https://pbs.twimg.com/profile_images/999017305869697024/eHwBaQtB_400x400.jpg" width="15"> [Solace](connect/connect-solace-source)
* <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-active-mq-source)
* <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-tibco-source)
* <img src="https://phelepjeremy.files.wordpress.com/2017/06/syslog-ng-logo.png?w=200" width="15"> [Syslog](connect/connect-syslog-source)
* <img src="https://opendistro.github.io/for-elasticsearch/assets/media/icons/javajdbc.png" width="15"> JDBC
    * <img src="https://banner2.cleanpng.com/20180803/abq/kisspng-mysql-cluster-database-management-system-专-题-咖-啡-与-代-码-5b640d8b2a2e53.6067051415332837231728.jpg" width="15"> [MySQL](connect/connect-jdbc-mysql-source)
    * <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-source)
    * <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-source)
    * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-source)
    * <img src="https://www.netclipart.com/pp/m/39-396469_sql-server-logo-png.png" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-source)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [AWS Redshift](connect/connect-jdbc-aws-redshift-source)
* <img src="https://avatars1.githubusercontent.com/u/1544528?s=400&v=4" width="15"> [MQTT](connect/connect-mqtt-source)
* <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [JMS TIBCO EMS](connect/connect-jms-tibco-source)
* <img src="https://influxdata.github.io/branding/img/downloads/influxdata-logo--symbol--pool.svg" width="15"> [InfluxDB](connect/connect-influxdb-source)
* <img src="http://www.pharmajournalist.com/wp-content/uploads/2017/11/splunk-logo.jpg" width="15"> [Splunk](connect/connect-splunk-source)
* <img src="https://cdn.worldvectorlogo.com/logos/rabbitmq.svg" width="15">  [RabbitMQ](connect/connect-rabbitmq-source)
* <img src="https://www.pinclipart.com/picdir/middle/23-237671_document-clipart-stack-papers-file-stack-icon-png.png" width="15"> [Spool Dir](connect/connect-spool-dir-source)
* <img src="https://cloud.google.com/images/social-icon-google-cloud-1200-630.png" width="15"> GCP
  * <img src="https://miro.medium.com/max/512/1*LXO5TpyB1GnCAE5-pz6L6Q.png" width="15"> [Pub/Sub](connect/connect-gcp-pubsub-source)
  * <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcp-gcs-source)
  * <img src="https://cdn.worldvectorlogo.com/logos/firebase-1.svg" width="15"> [Firebase](connect/connect-gcp-firebase-source)
* <img src="https://cdn.worldvectorlogo.com/logos/couchbase-1.svg" width="15"> [Couchbase](connect/connect-couchbase-source)
* <img src="https://cdn.iconscout.com/icon/free/png-512/sftp-1758329-1496548.png" width="15"> [SFTP](connect/connect-sftp-source)
* <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-mongodb-source)
* <img src="https://d3dr9sfxru4sde.cloudfront.net/i/k/apachekudu_logo_0716_345px.png" width="15"> [Kudu](connect/connect-kudu-source)
* <img src="https://coservit.com/servicenav/wp-content/uploads/sites/3/2019/05/SNMP_blue.png" width="15"> [SNMP](connect/connect-snmp-source)
* <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](connect/connect-servicenow-source)
* <img src="https://i7.pngguru.com/preview/604/568/971/logo-brand-design.jpg" width="15"> [Data Diode](connect/connect-datadiode-source-sink)

### ↗️ Sink

* <img src="https://mpng.pngfly.com/20190128/xso/kisspng-apache-hadoop-big-data-computer-software-data-scie-hadoop-and-tyrone-5c4f4554d98c79.8384600315486989648911.jpg" width="15"> Hadoop
    * <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 2](connect/connect-hdfs2-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 3](connect/connect-hdfs3-sink)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1200px-Amazon_Web_Services_Logo.svg.png" width="15"> AWS
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-s3.svg" width="15"> [S3](connect/connect-aws-s3-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [Redshift](connect/connect-aws-redshift-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-dynamodb.svg" width="15"> [DynamoDB](connect/connect-aws-dynamodb-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-lambda.svg" width="15"> [Lambda](connect/connect-aws-lambda-sink)
    * <img src="https://cdn.worldvectorlogo.com/logos/aws-cloudwatch.svg" width="15"> [CloudWatch Metrics](connect/connect-aws-cloudwatch-metrics-sink)
* <img src="https://cdn.shortpixel.ai/client/q_lossless,ret_img,w_600/https://spiraldatagroup.com.au/wp-content/uploads/2019/04/elastic-elasticsearch-logo-png-transparent-600x600.png" width="15"> [Elasticsearch](connect/connect-elasticsearch-sink)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/HTTP_logo.svg/440px-HTTP_logo.svg.png" width="15"> [HTTP](connect/connect-http-sink)
* <img src="https://clipartart.com/images/gcp-logo-clipart-6.png" width="15"> GCP
    * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/8/89/Google-BigQuery-Logo.svg/1200px-Google-BigQuery-Logo.svg.png" width="15"> [BigQuery](connect/connect-gcp-bigquery-sink)
    * <img src="https://img.stackshare.io/service/6672/google-cloud-functions.png" width="15"> [Cloud Functions](connect/connect-gcp-cloud-functions-sink)
    * <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcp-gcs-sink)
        * using [SASL_SSL](connect/connect-gcp-gcs-sink/README.md#with-sasl-ssl-authentication)
        * using [SSL](connect/connect-gcp-gcs-sink/README.md#with-ssl-authentication)
        * using [Kerberos GSSAPI](connect/connect-gcp-gcs-sink/README.md#with-kerberos-gssapi-authentication)
        * using [LDAP Authorizer SASL/PLAIN](connect/connect-gcp-gcs-sink/README.md#with-ldap-authorizer-with-saslplain)
    * <img src="https://cdn.worldvectorlogo.com/logos/firebase-1.svg" width="15"> [Firebase](connect/connect-gcp-firebase-sink)
    * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/Cloud-Spanner-Logo.svg/1200px-Cloud-Spanner-Logo.svg.png" width="15"> [Spanner](connect/connect-gcp-spanner-sink)
* <img src="https://pbs.twimg.com/profile_images/999017305869697024/eHwBaQtB_400x400.jpg" width="15"> [Solace](connect/connect-solace-sink)
* <img src="http://www.pharmajournalist.com/wp-content/uploads/2017/11/splunk-logo.jpg" width="15"> [Splunk](connect/connect-splunk-sink)
* <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-tibco-sink)
* <img src="https://developer.ibm.com/messaging/wp-content/uploads/sites/18/2017/09/IBM-MQ-Sticker-300x260.png" width="15"> [IBM MQ](connect/connect-ibm-mq-sink)
* <img src="https://avatars1.githubusercontent.com/u/1544528?s=400&v=4" width="15"> [MQTT](connect/connect-mqtt-sink)
* <img src="https://influxdata.github.io/branding/img/downloads/influxdata-logo--symbol--pool.svg" width="15"> [InfluxDB](connect/connect-influxdb-sink)
* <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Cassandra_logo.svg/1280px-Cassandra_logo.svg.png" width="15"> [Cassandra](connect/connect-cassandra-sink)
* <img src="https://opendistro.github.io/for-elasticsearch/assets/media/icons/javajdbc.png" width="15"> JDBC
    * <img src="https://banner2.cleanpng.com/20180803/abq/kisspng-mysql-cluster-database-management-system-专-题-咖-啡-与-代-码-5b640d8b2a2e53.6067051415332837231728.jpg" width="15"> [MySQL](connect/connect-jdbc-mysql-sink)
    * <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-sink)
    * <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-sink)
    * <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-sink)
    * <img src="https://www.netclipart.com/pp/m/39-396469_sql-server-logo-png.png" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-sink)
    * <img src="https://s3.amazonaws.com/awsmp-logos/vertica600x400.png" width="15"> [Vertica](connect/connect-jdbc-vertica-sink)
* <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-active-mq-sink)
* <img src="https://res-2.cloudinary.com/crunchbase-production/image/upload/c_lpad,h_256,w_256,f_auto,q_auto:eco/esdppsq3l6aqw0jdkpv3" width="15"> [OmniSci](connect/connect-omnisci-sink)
* <img src="http://logodesignfx.com/wp-content/uploads/2019/04/jms-logo-1.png" width="15"> JMS
    * <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-jms-active-mq-sink)
    * <img src="https://pbs.twimg.com/profile_images/999017305869697024/eHwBaQtB_400x400.jpg" width="15"> [Solace](connect/connect-jms-solace-sink)
    * <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-jms-tibco-sink)
* <img src="https://carlisletheacarlisletheatre.org/images/azure-logo-transparent-3.png" width="15"> Azure
    * <img src="https://dellenny.com/wp-content/uploads/2019/04/azure-storage-blob.png" width="15"> [Blob Storage](connect/connect-azure-blob-storage-sink)
    * <img src="https://2.bp.blogspot.com/-491wbRLWQAQ/WXZVyGJ0kaI/AAAAAAAAE3g/Cedi8ujEAWYJjgWILvvke6lwqUtqg665gCLcBGAs/s1600/azuredatalake.png" width="15"> [Data Lake Gen1](connect/connect-azure-data-lake-storage-gen1-sink)
    * <img src="https://2.bp.blogspot.com/-491wbRLWQAQ/WXZVyGJ0kaI/AAAAAAAAE3g/Cedi8ujEAWYJjgWILvvke6lwqUtqg665gCLcBGAs/s1600/azuredatalake.png" width="15"> [Data Lake Gen2](connect/connect-azure-data-lake-storage-gen2-sink)
* <img src="https://go.neo4j.com/rs/710-RRC-335/images/neo4j_logo_globe.png" width="15"> [Neo4j](connect/connect-neo4j-sink)
* <img src="https://cdn.worldvectorlogo.com/logos/couchbase-1.svg" width="15"> [Couchbase](connect/connect-couchbase-sink)
* <img src="https://cdn.iconscout.com/icon/free/png-512/sftp-1758329-1496548.png" width="15"> [SFTP](connect/connect-sftp-sink)
* <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-mongodb-sink)
* <img src="https://cdn.freebiesupply.com/logos/thumbs/2x/hbase-logo.png" width="15"> [HBase](connect/connect-hbase-sink)
* <img src="https://banner2.cleanpng.com/20180907/ska/kisspng-redis-memcached-database-caching-key-value-databas-redis-logo-svg-vector-amp-png-transparent-vect-5b9313b86aa329.3173207815363654964368.jpg" width="15"> [Redis](connect/connect-redis-sink)
* <img src="https://d3dr9sfxru4sde.cloudfront.net/i/k/apachekudu_logo_0716_345px.png" width="15"> [Kudu](connect/connect-kudu-sink)
* <img src="https://s3.amazonaws.com/awsmp-logos/vertica600x400.png" width="15"> [Vertica](connect/connect-vertica-sink)
* <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](connect/connect-servicenow-sink)
* <img src="https://min.io/resources/img/logo/MINIO_Bird.png" height="15">  [Minio](connect/connect-minio-s3-sink)

## ☁️ Confluent Cloud

### <img src="https://pbs.twimg.com/profile_images/979058850207641601/cLCehePZ.jpg" width="15"> [Confluent Cloud Demo](ccloud/ccloud-demo)

  * How to connect your components to Confluent Cloud
  * How to monitor your Confluent Cloud cluster
  * How to restrict access
  * etc...

![Diagram](./ccloud/ccloud-demo/images/diagram.png)

### 🔗 Kafka Connectors connected to Confluent Cloud

  * <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](ccloud/connect-servicenow-source) source
  * <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](ccloud/connect-servicenow-sink) sink


## 🔄 Confluent Replicator

Using Multi-Data-Center setup with `US` 🇺🇸 and `EUROPE` 🇪🇺 clusters.

* <img src="https://cdn.confluent.io/wp-content/themes/confluent/assets/images/connect-icon.png" width="15"> [Using Confluent Replicator as connector](replicator/connect)
  * Using [PLAINTEXT](environment/mdc-plaintext)
  * Using [SASL_PLAIN](environment/mdc-sasl-plain)
  * Using [Kerberos](environment/mdc-kerberos)
* 👾 [Using Confluent Replicator as executable](replicator/executable)
  * Using [PLAINTEXT](environment/mdc-plaintext)
  * Using [SASL_PLAIN](environment/mdc-sasl-plain)
  * Using [Kerberos](environment/mdc-kerberos)

## 🔐 Environments

Single cluster:

* [PLAINTEXT](environment/plaintext): no security
* [SASL_PLAIN](environment/sasl-plain): no SSL encryption, SASL/PLAIN authentication
* [SASL/SCRAM](environment/sasl-scram) no SSL encryption, SASL/SCRAM-SHA-256 authentication
* [SASL_SSL](environment/sasl-ssl): SSL encryption, SASL/PLAIN authentication
* [2WAY_SSL](environment/2way-ssl): SSL encryption, SSL authentication
* [Kerberos](environment/kerberos): no SSL encryption, Kerberos GSSAPI authentication
* [SSL_Kerberos](environment/ssl_kerberos) SSL encryption, Kerberos GSSAPI authentication
* [LDAP Authorizer with SASL/PLAIN](environment/ldap_authorizer_sasl_plain) no SSL encryption, SASL/PLAIN authentication, LDAP Authorizer for ACL authorization

Multi-Data-Center setup:

* [PLAINTEXT](environment/mdc-plaintext): no security
* [SASL_PLAIN](environment/mdc-sasl-plain): no SSL encryption, SASL/PLAIN authentication
* [Kerberos](environment/mdc-kerberos): no SSL encryption, Kerberos GSSAPI authentication

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

## Confluent Commercial

* [Tiered storage with AWS S3](other/tiered-storage-with-aws)
* [Tiered storage with Minio](other/tiered-storage-with-minio) (unsupported)


## 👾 Other Playgrounds

* [Confluent Rebalancer](other/rebalancer)
* [Confluent Replicator](connect/connect-replicator) [also with [SASL_SSL](connect/connect-replicator/README.md#with-sasl-ssl-authentication) and [2WAY_SSL](connect/connect-replicator/README.md#with-ssl-authentication)]
* Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP source)](other/connect-override-policy-sftp-source)
* Testing [Separate principals](https://docs.confluent.io/current/connect/security.html#separate-principals) (`connector.client.config.override.policy`) for [Source connector (SFTP sink)](other/connect-override-policy-sftp-sink)
* [Control Center in "Read-Only" mode](other/control-center-readonly-mode/)
* [Configuring Control Center with LDAP authentication](other/control-center-ldap-auth)
* [JMS Client](other/jms-client)
* [How to write logs to files when using docker-compose](other/write-logs-to-files)
* [Publish logs to kafka with Elastic Filebeat](other/filebeat-to-kafka)

## 📚 Useful Resources

* [A Kafka Story 📖](https://github.com/framiere/a-kafka-story): A step by step guide to use Kafka ecosystem (Kafka Connect, KSQL, Java Consumers/Producers, etc..) with Docker
* [Kafka Boom Boom 💥](https://github.com/Dabz/kafka-boom-boom): An attempt to break kafka
* [Kafka Security playbook 🔒](https://github.com/Dabz/kafka-security-playbook): demonstrates various security configurations with Docker
* [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter): Multi-Data-Center setup using Confluent [Replicator](https://docs.confluent.io/current/connect/kafka-connect-replicator/index.html)
* [Kafka Platform Prometheus 📊](https://github.com/jeanlouisboudart/kafka-platform-prometheus): Simple demo of how to monitor Kafka Platform using Prometheus and Grafana.