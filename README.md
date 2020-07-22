<!-- omit in toc -->
# <img src="https://www.docker.com/sites/default/files/d8/2019-07/vertical-logo-monochromatic.png" width="24"> <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Apache_kafka.svg/1200px-Apache_kafka.svg.png" width="16"> <img src="https://avatars3.githubusercontent.com/u/9439498?s=60&v=4" width="24"> kafka-docker-playground [![Build Status](https://travis-ci.com/vdesabou/kafka-docker-playground.svg?branch=master)](https://travis-ci.com/vdesabou/kafka-docker-playground)

Playground for Kafka/Confluent Docker experimentations...

----

## How to run

You just need to have [docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/)

If you want to run it on EC2 Instance, you can use the AWS CloudFormation template provided [here](cloudformation/README.md).

ℹ️ By default Confluent Platform version 5.5.1 is used, but you can test with another version (greater or equal to 5.0.0) simply by exporting `TAG` environment variable:

Example:

```bash
export TAG=5.3.2
```

----

<!-- omit in toc -->
## Table of Contents

- [How to run](#how-to-run)
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

- <img src="https://mpng.pngfly.com/20190128/xso/kisspng-apache-hadoop-big-data-computer-software-data-scie-hadoop-and-tyrone-5c4f4554d98c79.8384600315486989648911.jpg" width="15"> Hadoop
    - <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 2](connect/connect-hdfs2-source)
    - <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 3](connect/connect-hdfs3-source)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1200px-Amazon_Web_Services_Logo.svg.png" width="15"> AWS
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-s3.svg" width="15"> [S3](connect/connect-aws-s3-source)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-kinesis.svg" width="15"> [Kinesis](connect/connect-aws-kinesis-source)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-sqs.svg" width="15"> [SQS](connect/connect-aws-sqs-source)
        - using [SASL_SSL](connect/connect-aws-sqs-source/README.md#with-sasl-ssl-authentication)
        - using [SSL](connect/connect-aws-sqs-source/README.md#with-ssl-authentication)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-cloudwatch.svg" width="15"> [CloudWatch Logs](connect/connect-aws-cloudwatch-logs-source)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [AWS Redshift](connect/connect-jdbc-aws-redshift-source) (using JDBC)
- <img src="https://avatars3.githubusercontent.com/u/11964329?s=400&v=4" width="15"> Debezium
    - <img src="https://banner2.cleanpng.com/20180803/abq/kisspng-mysql-cluster-database-management-system-专-题-咖-啡-与-代-码-5b640d8b2a2e53.6067051415332837231728.jpg" width="15"> [MySQL](connect/connect-debezium-mysql-source)
    - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostgreSQL](connect/connect-debezium-postgresql-source)
    - <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-debezium-mongodb-source)
    - <img src="https://www.netclipart.com/pp/m/39-396469_sql-server-logo-png.png" width="15"> [SQL Server](connect/connect-debezium-sqlserver-source)
- <img src="https://developer.ibm.com/messaging/wp-content/uploads/sites/18/2017/09/IBM-MQ-Sticker-300x260.png" width="15"> [IBM MQ](connect/connect-ibm-mq-source)
- <img src="https://cdn.solace.com/wp-content/uploads/2014/05/solace-featured-image_logo-on-white.jpg" width="15"> [Solace](connect/connect-solace-source)
- <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-active-mq-source)
- <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-tibco-source)
- <img src="https://phelepjeremy.files.wordpress.com/2017/06/syslog-ng-logo.png?w=200" width="15"> [Syslog](connect/connect-syslog-source)
- <img src="https://opendistro.github.io/for-elasticsearch/assets/media/icons/javajdbc.png" width="15"> JDBC
    - <img src="https://banner2.cleanpng.com/20180803/abq/kisspng-mysql-cluster-database-management-system-专-题-咖-啡-与-代-码-5b640d8b2a2e53.6067051415332837231728.jpg" width="15"> [MySQL](connect/connect-jdbc-mysql-source)
    - <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-source)
    - <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-source)
    - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-source)
    - <img src="https://www.netclipart.com/pp/m/39-396469_sql-server-logo-png.png" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-source)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [AWS Redshift](connect/connect-jdbc-aws-redshift-source)
- <img src="https://avatars1.githubusercontent.com/u/1544528?s=400&v=4" width="15"> [MQTT](connect/connect-mqtt-source)
- <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [JMS TIBCO EMS](connect/connect-jms-tibco-source)
- <img src="https://influxdata.github.io/branding/img/downloads/influxdata-logo--symbol--pool.svg" width="15"> [InfluxDB](connect/connect-influxdb-source)
- <img src="http://www.pharmajournalist.com/wp-content/uploads/2017/11/splunk-logo.jpg" width="15"> [Splunk](connect/connect-splunk-source)
- <img src="https://cdn.worldvectorlogo.com/logos/rabbitmq.svg" width="15">  [RabbitMQ](connect/connect-rabbitmq-source)
- <img src="https://www.pinclipart.com/picdir/middle/23-237671_document-clipart-stack-papers-file-stack-icon-png.png" width="15"> [Spool Dir](connect/connect-spool-dir-source)
- <img src="https://cloud.google.com/images/social-icon-google-cloud-1200-630.png" width="15"> GCP
  - <img src="https://miro.medium.com/max/512/1*LXO5TpyB1GnCAE5-pz6L6Q.png" width="15"> [Pub/Sub](connect/connect-gcp-pubsub-source)
  - <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcp-gcs-source)
  - <img src="https://cdn.worldvectorlogo.com/logos/firebase-1.svg" width="15"> [Firebase](connect/connect-gcp-firebase-source)
- <img src="https://cdn.worldvectorlogo.com/logos/couchbase-1.svg" width="15"> [Couchbase](connect/connect-couchbase-source)
- <img src="https://cdn.iconscout.com/icon/free/png-512/sftp-1758329-1496548.png" width="15"> [SFTP](connect/connect-sftp-source)
- <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-mongodb-source)
- <img src="https://d3dr9sfxru4sde.cloudfront.net/i/k/apachekudu_logo_0716_345px.png" width="15"> [Kudu](connect/connect-kudu-source)
- <img src="https://coservit.com/servicenav/wp-content/uploads/sites/3/2019/05/SNMP_blue.png" width="15"> [SNMP](connect/connect-snmp-source)
- <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](connect/connect-servicenow-source)
- <img src="https://i7.pngguru.com/preview/604/568/971/logo-brand-design.jpg" width="15"> [Data Diode](connect/connect-datadiode-source-sink)
- <img src="https://cdn.worldvectorlogo.com/logos/azure-1.svg" width="15"> Azure
    - <img src="https://dellenny.com/wp-content/uploads/2019/04/azure-storage-blob.png" width="15"> [Blob Storage](connect/connect-azure-blob-storage-source)
    - <img src="https://www.element61.be/sites/default/files/competence/Microsoft%20Azure%20Event%20Hubs/1.png" width="15"> [Event Hubs](connect/connect-azure-event-hubs-source)
    - <img src="https://www.ciraltos.com/wp-content/uploads/2019/03/Service-Bus.png" width="15"> [Service Bus](connect/connect-azure-service-bus-source)
- <img src="https://www.cleo.com/sites/default/files/2018-10/logo_ftps-mod-11%20%281%29.svg" height="15"> [FTPS](connect/connect-ftps-source)

### ↗️ Sink

- <img src="https://mpng.pngfly.com/20190128/xso/kisspng-apache-hadoop-big-data-computer-software-data-scie-hadoop-and-tyrone-5c4f4554d98c79.8384600315486989648911.jpg" width="15"> Hadoop
    - <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 2](connect/connect-hdfs2-sink)
    - <img src="https://cdn.worldvectorlogo.com/logos/hadoop.svg" width="15"> [HDFS 3](connect/connect-hdfs3-sink)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1200px-Amazon_Web_Services_Logo.svg.png" width="15"> AWS
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-s3.svg" width="15"> [S3](connect/connect-aws-s3-sink)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-redshift-logo.svg" width="15"> [Redshift](connect/connect-aws-redshift-sink)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-dynamodb.svg" width="15"> [DynamoDB](connect/connect-aws-dynamodb-sink)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-lambda.svg" width="15"> [Lambda](connect/connect-aws-lambda-sink)
    - <img src="https://cdn.worldvectorlogo.com/logos/aws-cloudwatch.svg" width="15"> [CloudWatch Metrics](connect/connect-aws-cloudwatch-metrics-sink)
- <img src="https://cdn.shortpixel.ai/client/q_lossless,ret_img,w_600/https://spiraldatagroup.com.au/wp-content/uploads/2019/04/elastic-elasticsearch-logo-png-transparent-600x600.png" width="15"> [Elasticsearch](connect/connect-elasticsearch-sink)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/HTTP_logo.svg/440px-HTTP_logo.svg.png" width="15"> [HTTP](connect/connect-http-sink)
- <img src="https://clipartart.com/images/gcp-logo-clipart-6.png" width="15"> GCP
    - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/8/89/Google-BigQuery-Logo.svg/1200px-Google-BigQuery-Logo.svg.png" width="15"> [BigQuery](connect/connect-gcp-bigquery-sink)
    - <img src="https://img.stackshare.io/service/6672/google-cloud-functions.png" width="15"> [Cloud Functions](connect/connect-gcp-cloud-functions-sink)
    - <img src="https://miro.medium.com/max/256/1*lcRm2muyWDct3FW2drmptA.png" width="15"> [GCS](connect/connect-gcp-gcs-sink)
        - using [SASL_SSL](connect/connect-gcp-gcs-sink/README.md#with-sasl-ssl-authentication)
        - using [SSL](connect/connect-gcp-gcs-sink/README.md#with-ssl-authentication)
        - using [Kerberos GSSAPI](connect/connect-gcp-gcs-sink/README.md#with-kerberos-gssapi-authentication)
        - using [LDAP Authorizer SASL/PLAIN](connect/connect-gcp-gcs-sink/README.md#with-ldap-authorizer-with-saslplain)
        - using [RBAC environment SASL/PLAIN](connect/connect-gcp-gcs-sink/README.md#with-rbac-environment-with-saslplain)
    - <img src="https://cdn.worldvectorlogo.com/logos/firebase-1.svg" width="15"> [Firebase](connect/connect-gcp-firebase-sink)
    - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/Cloud-Spanner-Logo.svg/1200px-Cloud-Spanner-Logo.svg.png" width="15"> [Spanner](connect/connect-gcp-spanner-sink)
- <img src="https://cdn.solace.com/wp-content/uploads/2014/05/solace-featured-image_logo-on-white.jpg" width="15"> [Solace](connect/connect-solace-sink)
- <img src="http://www.pharmajournalist.com/wp-content/uploads/2017/11/splunk-logo.jpg" width="15"> [Splunk](connect/connect-splunk-sink)
- <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-tibco-sink)
- <img src="https://developer.ibm.com/messaging/wp-content/uploads/sites/18/2017/09/IBM-MQ-Sticker-300x260.png" width="15"> [IBM MQ](connect/connect-ibm-mq-sink)
- <img src="https://avatars1.githubusercontent.com/u/1544528?s=400&v=4" width="15"> [MQTT](connect/connect-mqtt-sink)
- <img src="https://influxdata.github.io/branding/img/downloads/influxdata-logo--symbol--pool.svg" width="15"> [InfluxDB](connect/connect-influxdb-sink)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Cassandra_logo.svg/1280px-Cassandra_logo.svg.png" width="15"> [Cassandra](connect/connect-cassandra-sink)
- <img src="https://opendistro.github.io/for-elasticsearch/assets/media/icons/javajdbc.png" width="15"> JDBC
    - <img src="https://banner2.cleanpng.com/20180803/abq/kisspng-mysql-cluster-database-management-system-专-题-咖-啡-与-代-码-5b640d8b2a2e53.6067051415332837231728.jpg" width="15"> [MySQL](connect/connect-jdbc-mysql-sink)
    - <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 11](connect/connect-jdbc-oracle11-sink)
    - <img src="https://www.stickee.co.uk/wp-content/uploads/2016/11/oracle-logo.jpg" width="15"> [Oracle 12](connect/connect-jdbc-oracle12-sink)
    - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Postgresql_elephant.svg/1080px-Postgresql_elephant.svg.png" width="15"> [PostGreSQL](connect/connect-jdbc-postgresql-sink)
    - <img src="https://www.netclipart.com/pp/m/39-396469_sql-server-logo-png.png" width="15"> [SQL Server](connect/connect-jdbc-sqlserver-sink)
    - <img src="https://s3.amazonaws.com/awsmp-logos/vertica600x400.png" width="15"> [Vertica](connect/connect-jdbc-vertica-sink)
    - <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/b/bb/Apache_Hive_logo.svg/1200px-Apache_Hive_logo.svg.png" width="15"> [Hive](connect/connect-jdbc-hive-sink)
- <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-active-mq-sink)
- <img src="https://res-2.cloudinary.com/crunchbase-production/image/upload/c_lpad,h_256,w_256,f_auto,q_auto:eco/esdppsq3l6aqw0jdkpv3" width="15"> [OmniSci](connect/connect-omnisci-sink)
- <img src="http://logodesignfx.com/wp-content/uploads/2019/04/jms-logo-1.png" width="15"> JMS
    - <img src="https://img.stackshare.io/service/1062/vlz__1_.png" width="15"> [ActiveMQ](connect/connect-jms-active-mq-sink)
    - <img src="https://cdn.solace.com/wp-content/uploads/2014/05/solace-featured-image_logo-on-white.jpg" width="15"> [Solace](connect/connect-jms-solace-sink)
    - <img src="https://media.glassdoor.com/sql/6280/tibco-software-squarelogo-1432805681756.png" width="15"> [TIBCO EMS](connect/connect-jms-tibco-sink)
- <img src="https://cdn.worldvectorlogo.com/logos/azure-1.svg" width="15"> Azure
    - <img src="https://dellenny.com/wp-content/uploads/2019/04/azure-storage-blob.png" width="15"> [Blob Storage](connect/connect-azure-blob-storage-sink)
    - <img src="https://2.bp.blogspot.com/-491wbRLWQAQ/WXZVyGJ0kaI/AAAAAAAAE3g/Cedi8ujEAWYJjgWILvvke6lwqUtqg665gCLcBGAs/s1600/azuredatalake.png" width="15"> [Data Lake Gen1](connect/connect-azure-data-lake-storage-gen1-sink)
    - <img src="https://2.bp.blogspot.com/-491wbRLWQAQ/WXZVyGJ0kaI/AAAAAAAAE3g/Cedi8ujEAWYJjgWILvvke6lwqUtqg665gCLcBGAs/s1600/azuredatalake.png" width="15"> [Data Lake Gen2](connect/connect-azure-data-lake-storage-gen2-sink)
    - <img src="https://encrypted-tbn0.gstatic.com/images?q=tbn%3AANd9GcSxw29wF6Zg3Re21ZCQGsaanMqOhEoLpul4yngctq13BNcg2BNc" width="15"> [SQL Data Warehouse](connect/connect-azure-sql-data-warehouse-sink)
    - <img src="https://acom.azurecomcdn.net/80C57D/blogmedia/blogmedia/2015/03/03/Azure-Search.png" width="15"> [Search](connect/connect-azure-search-sink)
- <img src="https://go.neo4j.com/rs/710-RRC-335/images/neo4j_logo_globe.png" width="15"> [Neo4j](connect/connect-neo4j-sink)
- <img src="https://cdn.worldvectorlogo.com/logos/couchbase-1.svg" width="15"> [Couchbase](connect/connect-couchbase-sink)
- <img src="https://cdn.iconscout.com/icon/free/png-512/sftp-1758329-1496548.png" width="15"> [SFTP](connect/connect-sftp-sink)
- <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](connect/connect-mongodb-sink)
- <img src="https://cdn.freebiesupply.com/logos/thumbs/2x/hbase-logo.png" width="15"> [HBase](connect/connect-hbase-sink)
- <img src="https://banner2.cleanpng.com/20180907/ska/kisspng-redis-memcached-database-caching-key-value-databas-redis-logo-svg-vector-amp-png-transparent-vect-5b9313b86aa329.3173207815363654964368.jpg" width="15"> [Redis](connect/connect-redis-sink)
- <img src="https://d3dr9sfxru4sde.cloudfront.net/i/k/apachekudu_logo_0716_345px.png" width="15"> [Kudu](connect/connect-kudu-sink)
- <img src="https://s3.amazonaws.com/awsmp-logos/vertica600x400.png" width="15"> [Vertica](connect/connect-vertica-sink)
- <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](connect/connect-servicenow-sink)
- <img src="https://min.io/resources/img/logo/MINIO_Bird.png" height="15"> [Minio](connect/connect-minio-s3-sink)
- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/3/38/Prometheus_software_logo.svg/1200px-Prometheus_software_logo.svg.png" height="15">  [Prometheus](connect/connect-prometheus-sink)
- <img src="https://docs.snowflake.com/fr/_images/logo-snowflake-sans-text.png" height="15">  [Snowflake](connect/connect-snowflake-sink)
- <img src="https://static-dotconferences-com.s3.amazonaws.com/editionpartnerships/datadog.png" height="15"> [Datadog Metrics](connect/connect-datadog-metrics-sink)
- <img src="https://www.cleo.com/sites/default/files/2018-10/logo_ftps-mod-11%20%281%29.svg" height="15"> [FTPS](connect/connect-ftps-sink)
- <img src="https://cdn.worldvectorlogo.com/logos/rabbitmq.svg" width="15">  [RabbitMQ](connect/connect-rabbitmq-sink)


## ☁️ Confluent Cloud

### [Confluent Cloud Demo](ccloud/ccloud-demo)

  - How to connect your components to Confluent Cloud
  - How to monitor your Confluent Cloud cluster
  - How to restrict access
  - etc...

![Diagram](./ccloud/ccloud-demo/images/diagram.png)

### 🔗 Kafka Connectors connected to Confluent Cloud

  - <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](ccloud/connect-servicenow-source) source
  - <img src="https://perspectium.mystagingwebsite.com/wp-content/uploads/2019/08/servicenow_logo_v2.png" width="15"> [ServiceNow](ccloud/connect-servicenow-sink) sink
  - <img src="https://res.cloudinary.com/practicaldev/image/fetch/s--HWZDLotH--/c_fill,f_auto,fl_progressive,h_320,q_auto,w_320/https://thepracticaldev.s3.amazonaws.com/uploads/user/profile_image/56177/3a0504e3-1139-4110-b903-08949636010a.jpg" width="15"> [MongoDB](ccloud/connect-debezium-mongodb-source) source
  - <img src="https://cdn.worldvectorlogo.com/logos/firebase-1.svg" width="15"> [Firebase](ccloud/connect-gcp-firebase-sink)

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

- <img src="https://cdn.confluent.io/wp-content/themes/confluent/assets/images/connect-icon.png" width="15"> [Using Confluent Replicator as connector](replicator/connect)
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
