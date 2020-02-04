# Publish logs to kafka with filebeat


## Objective

Example using `docker-compose` on how to write logs to Kafka using Elastic Filebeat.


## Results:

```
2020-02-04T14:55:02.938Z ===> ENV Variables ...
2020-02-04T14:55:02.943Z ALLOW_UNSIGNED=false
2020-02-04T14:55:02.943Z COMPONENT=control-center
2020-02-04T14:55:02.943Z CONFLUENT_DEB_VERSION=1
2020-02-04T14:55:02.943Z CONFLUENT_PLATFORM_LABEL=
2020-02-04T14:55:02.943Z CONFLUENT_VERSION=5.4.0
2020-02-04T14:55:02.944Z CONTROL_CENTER_AUTH_RESTRICTED_ROLES=Restricted
2020-02-04T14:55:02.944Z CONTROL_CENTER_BOOTSTRAP_SERVERS=broker:9092
2020-02-04T14:55:02.944Z CONTROL_CENTER_CONFIG_DIR=/etc/confluent-control-center
2020-02-04T14:55:02.944Z CONTROL_CENTER_CONNECT_CLUSTER=http://connect:8083
2020-02-04T14:55:02.944Z CONTROL_CENTER_DATA_DIR=/var/lib/confluent-control-center
2020-02-04T14:55:02.944Z CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=1
2020-02-04T14:55:02.944Z CONTROL_CENTER_KAFKA_BOOTSTRAP_SERVERS=broker:9092
2020-02-04T14:55:02.944Z CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS=1
2020-02-04T14:55:02.944Z CONTROL_CENTER_OPTS=-Djava.security.auth.login.config=/tmp/propertyfile.jaas
2020-02-04T14:55:02.945Z CONTROL_CENTER_REPLICATION_FACTOR=1
2020-02-04T14:55:02.945Z CONTROL_CENTER_REST_AUTHENTICATION_METHOD=BASIC
2020-02-04T14:55:02.946Z CONTROL_CENTER_REST_AUTHENTICATION_REALM=c3
2020-02-04T14:55:02.946Z CONTROL_CENTER_REST_AUTHENTICATION_ROLES=Administrators,Restricted
2020-02-04T14:55:02.946Z CONTROL_CENTER_SCHEMA_REGISTRY_URL=http://schema-registry:8081
2020-02-04T14:55:02.946Z CONTROL_CENTER_ZOOKEEPER_CONNECT=zookeeper:2181
2020-02-04T14:55:02.948Z CUB_CLASSPATH=/etc/confluent/docker/docker-utils.jar
2020-02-04T14:55:02.948Z HOME=/root
2020-02-04T14:55:02.948Z HOSTNAME=control-center
2020-02-04T14:55:02.949Z KAFKA_VERSION=
2020-02-04T14:55:02.949Z LANG=C.UTF-8
2020-02-04T14:55:02.949Z PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
2020-02-04T14:55:02.949Z PWD=/
2020-02-04T14:55:02.949Z PYTHON_PIP_VERSION=8.1.2
2020-02-04T14:55:02.949Z PYTHON_VERSION=2.7.9-1
2020-02-04T14:55:02.949Z SCALA_VERSION=2.12
2020-02-04T14:55:02.950Z SHLVL=1
2020-02-04T14:55:02.950Z ZULU_OPENJDK_VERSION=8=8.38.0.13
2020-02-04T14:55:02.950Z _=/usr/bin/env
2020-02-04T14:55:02.950Z ===> User
2020-02-04T14:55:02.950Z uid=0(root) gid=0(root) groups=0(root)
2020-02-04T14:55:02.950Z ===> Configuring ...
2020-02-04T14:55:02.950Z ===> Check if /etc/confluent-control-center is writable ...
2020-02-04T14:55:02.950Z ===> Check if /var/lib/confluent-control-center is writable ...
2020-02-04T14:55:02.950Z ===> Running preflight checks ...
2020-02-04T14:55:02.951Z ===> Check if Kafka is healthy ...
2020-02-04T14:55:02.951Z ===> Launching ...
2020-02-04T14:55:02.951Z ===> Launching control-center ...
2020-02-04T14:55:02.951Z [2020-01-24 08:13:10,045] WARN Invalid value 1 for configuration confluent.controlcenter.internal.topics.replication: Value must be at least 3 (io.confluent.controlcenter.ControlCenterConfig)
2020-02-04T14:55:02.951Z [2020-01-24 08:13:10,047] WARN Invalid value 1 for configuration confluent.controlcenter.internal.topics.replication: Value must be at least 3 (io.confluent.controlcenter.ControlCenterConfig)
2020-02-04T14:55:02.951Z [2020-01-24 08:13:10,047] INFO ControlCenterConfig values:
2020-02-04T14:55:02.951Z        auth.bearer.roles.claim =
2020-02-04T14:55:02.951Z        bootstrap.servers = [broker:9092]
2020-02-04T14:55:02.952Z        confluent.controlcenter.alert.cluster.down.autocreate = false
2020-02-04T14:55:02.952Z        confluent.controlcenter.alert.cluster.down.send.rate = 12
2020-02-04T14:55:02.952Z        confluent.controlcenter.alert.cluster.down.to.email =
2020-02-04T14:55:02.952Z        confluent.controlcenter.alert.cluster.down.to.pagerduty.integrationkey =
2020-02-04T14:55:02.952Z        confluent.controlcenter.alert.cluster.down.to.webhookurl.slack =
2020-02-04T14:55:02.952Z        confluent.controlcenter.alert.max.trigger.events = 1000
2020-02-04T14:55:02.952Z        confluent.controlcenter.auth.bearer.issuer = Confluent
2020-02-04T14:55:02.952Z        confluent.controlcenter.auth.restricted.roles = [Restricted]
2020-02-04T14:55:02.952Z        confluent.controlcenter.auth.session.expiration.ms = 0
2020-02-04T14:55:02.952Z        confluent.controlcenter.broker.config.edit.enable = true
2020-02-04T14:55:02.952Z        confluent.controlcenter.command.streams.start.timeout = 300000
2020-02-04T14:55:02.952Z        confluent.controlcenter.command.topic = _confluent-command
2020-02-04T14:55:02.953Z        confluent.controlcenter.command.topic.replication = 1
2020-02-04T14:55:02.953Z        confluent.controlcenter.command.topic.retention.ms = 259200000
2020-02-04T14:55:02.953Z        confluent.controlcenter.connect.cluster = [http://connect:8083]
2020-02-04T14:55:02.953Z        confluent.controlcenter.consumers.view.enable = true
2020-02-04T14:55:02.953Z        confluent.controlcenter.data.dir = /var/lib/confluent-control-center
2020-02-04T14:55:02.953Z        confluent.controlcenter.deprecated.views.enable = false
2020-02-04T14:55:02.953Z        confluent.controlcenter.disk.skew.warning.min.bytes = 1073741824
2020-02-04T14:55:02.953Z        confluent.controlcenter.id = 1
2020-02-04T14:55:02.953Z        confluent.controlcenter.internal.streams.start.timeout = 21600000
2020-02-04T14:55:02.953Z        confluent.controlcenter.internal.topics.changelog.segment.bytes = 134217728
2020-02-04T14:55:02.953Z        confluent.controlcenter.internal.topics.partitions = 1
2020-02-04T14:55:02.953Z        confluent.controlcenter.internal.topics.replication = 1
2020-02-04T14:55:02.953Z        confluent.controlcenter.internal.topics.retention.bytes = -1
2020-02-04T14:55:02.953Z        confluent.controlcenter.internal.topics.retention.ms = 604800000
2020-02-04T14:55:02.953Z        confluent.controlcenter.ksql.advertised.url = []
2020-02-04T14:55:02.954Z        confluent.controlcenter.ksql.enable = true
2020-02-04T14:55:02.954Z        confluent.controlcenter.ksql.url = []
2020-02-04T14:55:02.954Z        confluent.controlcenter.license.manager = _confluent-controlcenter-license-manager-5-4-0
2020-02-04T14:55:02.954Z        confluent.controlcenter.license.manager.enable = true
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.bounce.address =
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.enabled = false
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.from = c3@confluent.io
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.host.name = localhost
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.password =
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.port = 587
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.ssl.checkserveridentity = false
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.starttls.required = false
2020-02-04T14:55:02.954Z        confluent.controlcenter.mail.username =
2020-02-04T14:55:02.955Z        confluent.controlcenter.name = _confluent-controlcenter-5-4-0
2020-02-04T14:55:02.955Z        confluent.controlcenter.proactive.support.ui.cta.enable = false
2020-02-04T14:55:02.955Z        confluent.controlcenter.rest.advertised.url =
2020-02-04T14:55:02.955Z        confluent.controlcenter.rest.compression.enable = true
2020-02-04T14:55:02.955Z        confluent.controlcenter.rest.hsts.enable = true
2020-02-04T14:55:02.955Z        confluent.controlcenter.rest.port = 9021
2020-02-04T14:55:02.956Z        confluent.controlcenter.schema.registry.enable = true
2020-02-04T14:55:02.956Z        confluent.controlcenter.schema.registry.url = [http://schema-registry:8081]
2020-02-04T14:55:02.956Z        confluent.controlcenter.streams.cache.max.bytes.buffering = 1073741824
2020-02-04T14:55:02.956Z        confluent.controlcenter.streams.consumer.session.timeout.ms = 60000
2020-02-04T14:55:02.956Z        confluent.controlcenter.streams.num.stream.threads = 8
2020-02-04T14:55:02.957Z        confluent.controlcenter.streams.producer.compression.type = lz4
Processed a total of 100 messages
```

## Using Confluent Cloud

Create the topic `topic-log` and edit file `filebeat.yml` with:

```yml
  # kafka
  # publishing to 'topic-log' topic
  hosts: ["<BOOTSTRAP SERVER>"]
  username: '<API KEY>'
  password: '<API SECRET>'
  ssl:
    enabled: true
    certificate_authorities: /etc/ssl/certs/ca-bundle.crt
```

## Credits

This is based on this [article](https://medium.com/rahasak/publish-logs-to-kafka-with-filebeat-74497ef7dafe)

