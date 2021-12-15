# Testing a potential workaround for RBAC/LDAP case sensitivity issue



## How to run

Simply run:

```
$ ./start-plaintext.sh
```

or

```
$ ./start-rbac.sh
```

## With PLAINTEXT

![Plaintext](plaintext.jpg)

## With RBAC

`superUser/superUser`

![RBAC](rbac.jpg)

## Properties

broker:

```
advertised.listeners=INTERNAL://broker:9092,TOKEN://broker:10091
authorizer.class.name=io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer
broker.id=1
confluent.authorizer.access.rule.providers=CONFLUENT,ZK_ACL
confluent.authorizer.group.provider=RBAC
confluent.balancer.enable=true
confluent.balancer.topic.replication.factor=1
confluent.license.topic.replication.factor=1
confluent.metadata.server.advertised.listeners=http://broker:8091
confluent.metadata.server.authentication.method=BEARER
confluent.metadata.server.listeners=http://0.0.0.0:8091
confluent.metadata.server.public.key.path=/tmp/conf/public.pem
confluent.metadata.server.token.auth.enable=true
confluent.metadata.server.token.key.path=/tmp/conf/keypair.pem
confluent.metadata.server.token.max.lifetime.ms=3600000
confluent.metadata.server.token.signature.algorithm=RS256
confluent.metadata.topic.replication.factor=1
confluent.metrics.enable=true
confluent.metrics.reporter.bootstrap.servers=broker:9092
confluent.metrics.reporter.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";
confluent.metrics.reporter.sasl.mechanism=PLAIN
confluent.metrics.reporter.security.protocol=SASL_PLAINTEXT
confluent.metrics.reporter.topic.replicas=1
confluent.support.customer.id=anonymous
inter.broker.listener.name=INTERNAL
jmx.hostname=localhost
jmx.port=10000
ldap.com.sun.jndi.ldap.read.timeout=3000
ldap.group.member.attribute.pattern=cn=(.*),ou=users,dc=confluentdemo,dc=io
ldap.group.member.attribute=memberUid
ldap.group.name.attribute=cn
ldap.group.object.class=posixGroup
ldap.group.search.base=ou=groups,dc=confluentdemo,dc=io
ldap.java.naming.factory.initial=com.sun.jndi.ldap.LdapCtxFactory
ldap.java.naming.provider.url=ldaps://openldap:636
ldap.java.naming.security.authentication=simple
ldap.java.naming.security.credentials=admin
ldap.java.naming.security.principal=cn=admin,dc=confluentdemo,dc=io
ldap.java.naming.security.protocol=SSL
ldap.search.mode=GROUPS
ldap.ssl.truststore.location=/tmp/ldap_certs/ldap_truststore.jks
ldap.ssl.truststore.password=welcome123
ldap.user.name.attribute=uid
ldap.user.object.class=inetOrgPerson
ldap.user.search.base=ou=users,dc=confluentdemo,dc=io
listener.name.internal.plain.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
listener.name.token.oauthbearer.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
listener.name.token.oauthbearer.sasl.login.callback.handler.class=io.confluent.kafka.server.plugins.auth.token.TokenBearerServerLoginCallbackHandler
listener.name.token.oauthbearer.sasl.server.callback.handler.class=io.confluent.kafka.server.plugins.auth.token.TokenBearerValidatorCallbackHandler
listener.security.protocol.map=INTERNAL:SASL_PLAINTEXT,TOKEN:SASL_PLAINTEXT
listeners=INTERNAL://:9092,TOKEN://:10091
log.dirs=/var/lib/kafka/data
metric.reporters=io.confluent.metrics.reporter.ConfluentMetricsReporter
offsets.topic.replication.factor=1
password="admin-secret" \
publicKeyPath="/tmp/conf/public.pem";
sasl.enabled.mechanisms=PLAIN, OAUTHBEARER
sasl.mechanism.inter.broker.protocol=PLAIN
super.users=User:admin;User:mds;User:superUser;User:ANONYMOUS
transaction.state.log.min.isr=1
transaction.state.log.replication.factor=1
user_admin="admin-secret" \
user_mds="mds-secret";
username="admin" \
zookeeper.connect=zookeeper:2181
zookeeper.set.acl=true
```

control-center:

```
bootstrap.servers=broker:10091
confluent.controlcenter.command.topic.replication=1
confluent.controlcenter.config.dir=/etc/confluent-control-center
confluent.controlcenter.connect.cluster=http://connect:8083
confluent.controlcenter.connect.connect1.cluster=http://connect:8083
confluent.controlcenter.connect.myconnect.cluster=http://connect:8083
confluent.controlcenter.data.dir=/var/lib/confluent-control-center
confluent.controlcenter.internal.topics.partitions=1
confluent.controlcenter.internal.topics.replication=1
confluent.controlcenter.kafka.bootstrap.servers=broker:9092
confluent.controlcenter.kafka.mycluster.bootstrap.servers=broker:10091
confluent.controlcenter.kafka.mycluster.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
confluent.controlcenter.kafka.mycluster.sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
confluent.controlcenter.kafka.mycluster.sasl.mechanism=OAUTHBEARER
confluent.controlcenter.kafka.mycluster.security.protocol=SASL_PLAINTEXT
confluent.controlcenter.ksql.advertised.url=http://127.0.0.1:8088
confluent.controlcenter.ksql.myksql.advertised.url=http://127.0.0.1:8088
confluent.controlcenter.ksql.myksql.url=http://ksqldb-server:8088
confluent.controlcenter.ksql.url=http://ksqldb-server:8088
confluent.controlcenter.replication.factor=1
confluent.controlcenter.rest.authentication.method=BEARER
confluent.controlcenter.schema.registry.url=http://schema-registry:8081
confluent.controlcenter.streams.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
confluent.controlcenter.streams.sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
confluent.controlcenter.streams.sasl.mechanism=OAUTHBEARER
confluent.controlcenter.streams.security.protocol=SASL_PLAINTEXT
confluent.controlcenter.ui.autoupdate.enable=false
confluent.metadata.basic.auth.user.info=controlcenterAdmin:controlcenterAdmin
confluent.metadata.bootstrap.server.urls=http://broker:8091
confluent.metrics.topic.replication=1
confluent.metrics.topic.replication=1
confluent.monitoring.interceptor.topic.partitions=1
confluent.monitoring.interceptor.topic.replication=1
metadataServerUrls="http://broker:8091";
metadataServerUrls="http://broker:8091";
password="controlcenterAdmin" \
password="controlcenterAdmin" \
public.key.path=/tmp/conf/public.pem
username="controlcenterAdmin" \
username="controlcenterAdmin" \
zookeeper.connect=zookeeper:2181
```