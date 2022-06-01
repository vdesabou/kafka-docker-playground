#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#${DIR}/../../environment/mdc-sasl-plain/start.sh "${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml"

docker-compose -f ${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml build
docker-compose -f ${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml down -v --remove-orphans
docker-compose -f ${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml up -d


../../scripts/wait-for-connect-and-controlcenter.sh connect-us
../../scripts/wait-for-connect-and-controlcenter.sh connect-europe

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE --producer.config /etc/kafka/client.properties

log "create replicator on connect-europe (PLAIN) with src=europe and dest=us (PLAINTEXT)"
docker container exec connect-europe \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.kafka.security.protocol" : "SASL_PLAINTEXT",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "src.kafka.sasl.mechanism": "PLAIN",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "dest.kafka.sasl.mechanism": "GSSAPI",
          "dest.kafka.security.protocol": "PLAINTEXT",
          "confluent.topic.replication.factor": 1,
          "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
          "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "confluent.topic.sasl.mechanism": "PLAIN",
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE",

          "admin.override.bootstrap.servers":"broker-us:9092",
          "admin.override.sasl.mechanism": "GSSAPI",
          "admin.override.security.protocol": "PLAINTEXT"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

sleep 120

log "Verify we have received the data in is sales_EUROPE in US"
docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_EUROPE" --from-beginning --max-messages 10 


# [2022-06-01 13:54:38,660] INFO [replicate-europe-to-us|worker] ReplicatorSourceConnectorConfig values: 
#         confluent.license = 
#         confluent.topic = _confluent-command
#         dest.kafka.bootstrap.servers = [broker-us:9092]
#         dest.kafka.client.id = 
#         dest.kafka.connections.max.idle.ms = 540000
#         dest.kafka.metric.reporters = []
#         dest.kafka.metrics.num.samples = 2
#         dest.kafka.metrics.sample.window.ms = 30000
#         dest.kafka.receive.buffer.bytes = 65536
#         dest.kafka.reconnect.backoff.ms = 50
#         dest.kafka.request.timeout.ms = 30000
#         dest.kafka.retry.backoff.ms = 100
#         dest.kafka.sasl.client.callback.handler.class = null
#         dest.kafka.sasl.jaas.config = null
#         dest.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         dest.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         dest.kafka.sasl.kerberos.service.name = null
#         dest.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         dest.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         dest.kafka.sasl.login.callback.handler.class = null
#         dest.kafka.sasl.login.class = null
#         dest.kafka.sasl.login.refresh.buffer.seconds = 300
#         dest.kafka.sasl.login.refresh.min.period.seconds = 60
#         dest.kafka.sasl.login.refresh.window.factor = 0.8
#         dest.kafka.sasl.login.refresh.window.jitter = 0.05
#         dest.kafka.sasl.mechanism = GSSAPI
#         dest.kafka.security.protocol = PLAINTEXT
#         dest.kafka.send.buffer.bytes = 131072
#         dest.kafka.ssl.cipher.suites = null
#         dest.kafka.ssl.enabled.protocols = [TLSv1.2]
#         dest.kafka.ssl.endpoint.identification.algorithm = https
#         dest.kafka.ssl.engine.factory.class = null
#         dest.kafka.ssl.key.password = null
#         dest.kafka.ssl.keymanager.algorithm = SunX509
#         dest.kafka.ssl.keystore.certificate.chain = null
#         dest.kafka.ssl.keystore.key = null
#         dest.kafka.ssl.keystore.location = null
#         dest.kafka.ssl.keystore.password = null
#         dest.kafka.ssl.keystore.type = JKS
#         dest.kafka.ssl.protocol = TLSv1.2
#         dest.kafka.ssl.provider = null
#         dest.kafka.ssl.secure.random.implementation = null
#         dest.kafka.ssl.trustmanager.algorithm = PKIX
#         dest.kafka.ssl.truststore.certificates = null
#         dest.kafka.ssl.truststore.location = null
#         dest.kafka.ssl.truststore.password = null
#         dest.kafka.ssl.truststore.type = JKS
#         dest.topic.replication.factor = 0
#         dest.zookeeper.connect = 
#         dest.zookeeper.connection.timeout.ms = 6000
#         dest.zookeeper.session.timeout.ms = 6000
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         offset.start = connect
#         offset.timestamps.commit = true
#         offset.topic.commit = true
#         offset.translator.batch.period.ms = 60000
#         offset.translator.batch.size = 1
#         offset.translator.tasks.max = -1
#         offset.translator.tasks.separate = false
#         provenance.header.enable = true
#         provenance.header.filter.overrides = 
#         schema.registry.client.basic.auth.credentials.source = URL
#         schema.registry.client.basic.auth.user.info = [hidden]
#         schema.registry.max.schemas.per.subject = 1000
#         schema.registry.topic = null
#         schema.registry.url = null
#         schema.subject.translator.class = null
#         src.consumer.check.crcs = true
#         src.consumer.fetch.max.bytes = 52428800
#         src.consumer.fetch.max.wait.ms = 500
#         src.consumer.fetch.min.bytes = 1
#         src.consumer.interceptor.classes = []
#         src.consumer.max.partition.fetch.bytes = 1048576
#         src.consumer.max.poll.interval.ms = 300000
#         src.consumer.max.poll.records = 500
#         src.header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.kafka.bootstrap.servers = [broker-europe:9092]
#         src.kafka.client.id = 
#         src.kafka.connections.max.idle.ms = 540000
#         src.kafka.metric.reporters = []
#         src.kafka.metrics.num.samples = 2
#         src.kafka.metrics.sample.window.ms = 30000
#         src.kafka.receive.buffer.bytes = 65536
#         src.kafka.reconnect.backoff.ms = 50
#         src.kafka.request.timeout.ms = 30000
#         src.kafka.retry.backoff.ms = 100
#         src.kafka.sasl.client.callback.handler.class = null
#         src.kafka.sasl.jaas.config = [hidden]
#         src.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         src.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         src.kafka.sasl.kerberos.service.name = null
#         src.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         src.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         src.kafka.sasl.login.callback.handler.class = null
#         src.kafka.sasl.login.class = null
#         src.kafka.sasl.login.refresh.buffer.seconds = 300
#         src.kafka.sasl.login.refresh.min.period.seconds = 60
#         src.kafka.sasl.login.refresh.window.factor = 0.8
#         src.kafka.sasl.login.refresh.window.jitter = 0.05
#         src.kafka.sasl.mechanism = PLAIN
#         src.kafka.security.protocol = SASL_PLAINTEXT
#         src.kafka.send.buffer.bytes = 131072
#         src.kafka.ssl.cipher.suites = null
#         src.kafka.ssl.enabled.protocols = [TLSv1.2]
#         src.kafka.ssl.endpoint.identification.algorithm = https
#         src.kafka.ssl.engine.factory.class = null
#         src.kafka.ssl.key.password = null
#         src.kafka.ssl.keymanager.algorithm = SunX509
#         src.kafka.ssl.keystore.certificate.chain = null
#         src.kafka.ssl.keystore.key = null
#         src.kafka.ssl.keystore.location = null
#         src.kafka.ssl.keystore.password = null
#         src.kafka.ssl.keystore.type = JKS
#         src.kafka.ssl.protocol = TLSv1.2
#         src.kafka.ssl.provider = null
#         src.kafka.ssl.secure.random.implementation = null
#         src.kafka.ssl.trustmanager.algorithm = PKIX
#         src.kafka.ssl.truststore.certificates = null
#         src.kafka.ssl.truststore.location = null
#         src.kafka.ssl.truststore.password = null
#         src.kafka.ssl.truststore.type = JKS
#         src.key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         topic.auto.create = true
#         topic.blacklist = []
#         topic.config.sync = true
#         topic.config.sync.interval.ms = 120000
#         topic.create.backoff.ms = 120000
#         topic.poll.interval.ms = 120000
#         topic.preserve.partitions = true
#         topic.regex = null
#         topic.rename.format = ${topic}
#         topic.timestamp.type = CreateTime
#         topic.whitelist = [sales_EUROPE]
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (io.confluent.connect.replicator.ReplicatorSourceConnectorConfig:361)

# [2022-06-01 13:54:38,662] INFO [replicate-europe-to-us|worker] AdminClientConfig values: 
#         bootstrap.servers = [broker-us:9092]
#         client.dns.lookup = use_all_dns_ips
#         client.id = 
#         connections.max.idle.ms = 300000
#         default.api.timeout.ms = 60000
#         metadata.max.age.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         receive.buffer.bytes = 65536
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 100
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = [hidden]
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = PLAIN
#         security.protocol = SASL_PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.2
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#  (org.apache.kafka.clients.admin.AdminClientConfig:361)
# [2022-06-01 13:54:38,670] ERROR [replicate-europe-to-us|worker] [AdminClient clientId=adminclient-18] Connection to node -1 (broker-us/192.168.192.6:9092) failed authentication due to: Unexpected handshake request with client mechanism PLAIN, enabled mechanisms are [] (org.apache.kafka.clients.NetworkClient:785)



#  ../../scripts/get-properties.sh connect-europe                                               
# bootstrap.servers=broker-europe:9092
# config.storage.replication.factor=1
# config.storage.topic=connect-europe.config
# connector.client.config.override.policy=All
# consumer.confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092
# consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor
# consumer.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="connect" password="connect-secret";
# consumer.sasl.mechanism=PLAIN
# consumer.security.protocol=SASL_PLAINTEXT
# group.id=connect-europe
# internal.key.converter.schemas.enable=false
# internal.key.converter=org.apache.kafka.connect.json.JsonConverter
# internal.value.converter.schemas.enable=false
# internal.value.converter=org.apache.kafka.connect.json.JsonConverter
# key.converter=org.apache.kafka.connect.json.JsonConverter
# log4j.appender.stdout.layout.conversionpattern=[%d] %p %X{connector.context}%m (%c:%L)%n
# log4j.loggers=org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR
# offset.storage.replication.factor=1
# offset.storage.topic=connect-europe.offsets
# plugin.path=/usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator
# producer.client.id=connect-worker-producer-europe
# producer.confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092
# producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
# producer.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="connect" password="connect-secret";
# producer.sasl.mechanism=PLAIN
# producer.security.protocol=SASL_PLAINTEXT
# rest.advertised.host.name=connect-europe
# rest.extension.classes=io.confluent.connect.replicator.monitoring.ReplicatorMonitoringExtension
# rest.port=8083
# sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="connect" password="connect-secret";
# sasl.mechanism=PLAIN
# security.protocol=SASL_PLAINTEXT
# status.storage.replication.factor=1
# status.storage.topic=connect-europe.status
# topic.creation.enable=true
# value.converter=org.apache.kafka.connect.json.JsonConverter