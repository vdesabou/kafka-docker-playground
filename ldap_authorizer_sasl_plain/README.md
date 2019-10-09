# LDAP Authorizer with SASL/PLAIN

## Description

This is a deployment with no SSL encryption, SASL_PLAINTEXT as the security protocol for the Kafka broker and Kafka clients with SASL/PLAIN as the SASL mechanism:

* 1 zookeeper
* 1 broker
* 1 connect
* 1 schema-registry
* 1 control-center

The goal is to test [LDAP authorizer](https://docs.confluent.io/current/security/ldap-authorizer/quickstart.html#using-the-ldap-auth-long) in this config.

## How to run

Simply run:

```
$ ./start.sh
```

## Explanations

LDAP server (using docker image `osixia/openldap:1.2.3`) is loading at startup `.ldif`files in `./custom`directory:

The users in the example are:

* `broker` : for brokers (groups are not used in the example for authorization of brokers, but broker authorization could also be configured using groups if required)
* alice and barnie are in `Kafka Developers` group
* charlie is **not** in `Kafka Developers` group

Activate the Plugin:

```yml
KAFKA_AUTHORIZER_CLASS_NAME: io.confluent.kafka.security.ldap.authorizer.LdapAuthorizer
```

Configure listeners for broker with SASL/PLAIN:

```yml
KAFKA_LISTENERS: SASL_PLAINTEXT://:9092
KAFKA_ADVERTISED_LISTENERS: SASL_PLAINTEXT://broker:9092
KAFKA_SASL_ENABLED_MECHANISMS: PLAIN
KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL: PLAIN
KAFKA_SECURITY_INTER_BROKER_PROTOCOL: SASL_PLAINTEXT
KAFKA_OPTS: "-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf"
# Set Kafka broker user as super user (alternatively, set ACLs before starting brokers)
KAFKA_SUPER_USERS: User:broker;User:schemaregistry;User:controlcenter
```

Configure LDAP Authorizer:

```yml
# Configure authorizer
KAFKA_AUTHORIZER_CLASS_NAME: io.confluent.kafka.security.ldap.authorizer.LdapAuthorizer
# LDAP provider URL
KAFKA_LDAP_JAVA_NAMING_PROVIDER_URL: ldap://ldap:389/DC=CONFLUENT,DC=IO
# Refresh interval for LDAP cache. If set to zero, persistent search is used.
# Reduced this value from the default 60000ms (60sec) to 10sec to detect
# faster the updates done in the LDAP database
KAFKA_LDAP_REFRESH_INTERVAL_MS: 10000
# Security authentication protocol for LDAP context
KAFKA_LDAP_JAVA_NAMING_SECURITY_AUTHENTICATION: SIMPLE
KAFKA_LDAP_JAVA_NAMING_SECURITY_PRINCIPAL: cn=admin,dc=confluent,dc=io
KAFKA_LDAP_JAVA_NAMING_SECURITY_CREDENTIALS: admin
# Remember that LDAP works in a context. The search base is ou=groups,dc=confluent,dc=io
# But since my URL is ldap://ldap:389/DC=CONFLUENT,DC=IO, we are already working in the dc=confluent,dc=io context
KAFKA_LDAP_GROUP_SEARCH_BASE: ou=groups
# Object class for groups
KAFKA_LDAP_GROUP_OBJECT_CLASS: posixGroup
KAFKA_LDAP_GROUP_SEARCH_SCOPE: 2
# Name of the attribute from which group name used in ACLs is obtained
KAFKA_LDAP_GROUP_NAME_ATTRIBUTE: cn
# Regex pattern to obtain group name used in ACLs from the attribute
KAFKA_LDAP_GROUP_NAME_ATTRIBUTE_PATTERN:
# Name of the attribute from which group members (user principals) are obtained
KAFKA_LDAP_GROUP_MEMBER_ATTRIBUTE: memberUid
# Regex pattern to obtain user principal from group member attribute
KAFKA_LDAP_GROUP_MEMBER_ATTRIBUTE_PATTERN: cn=(.*),ou=users,dc=confluent,dc=io
```

### Test LDAP group-based authorization

Create topic testtopic

```bash
$ docker container exec broker kafka-topics --create --topic testtopic --partitions 10 --replication-factor 1 --zookeeper zookeeper:2181
```

Run console producer without authorizing user `alice`: SHOULD FAIL

```bash
$ docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/alice.properties << EOF
message Alice
EOF
```

Result:

```
[2019-10-09 16:12:11,385] WARN [Producer clientId=console-producer] Error while fetching metadata with correlation id 1 : {testtopic=TOPIC_AUTHORIZATION_FAILED} (org.apache.kafka.clients.NetworkClient)
[2019-10-09 16:12:11,391] ERROR [Producer clientId=console-producer] Topic authorization failed for topics [testtopic] (org.apache.kafka.clients.Metadata)
[2019-10-09 16:12:11,394] ERROR Error when sending message to topic testtopic with key: null, value: 13 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.TopicAuthorizationException: Not authorized to access topics: [testtopic]
```

Authorize group `Group:Kafka Developers`

```bash
$ docker container exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --topic=testtopic --producer --allow-principal="Group:Kafka Developers"
```

Rerun producer for `alice`: SHOULD BE SUCCESS

```bash
$ docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/alice.properties << EOF
message Alice
EOF
```

Run console consumer without access to consumer group: SHOULD FAIL

Note: Consume should fail authorization since neither user alice nor the group Kafka Developers that alice belongs to has authorization to consume using the group test-consumer-group

```bash
$ docker container exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/alice.properties --max-messages 1
```

Results:

```
[2019-10-09 16:12:21,356] ERROR Error processing message, terminating consumer process:  (kafka.tools.ConsoleConsumer$)
org.apache.kafka.common.errors.GroupAuthorizationException: Not authorized to access group: test-consumer-group
```


Authorize group and rerun consumer

```bash
$ docker container exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --topic=testtopic --group test-consumer-group --allow-principal="Group:Kafka Developers"

$ docker container exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/alice.properties --max-messages 1
```

Run console producer with authorized user `barnie` (barnie is in group): SHOULD BE SUCCESS

```bash
$ docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/barnie.properties << EOF
message Barnie
EOF
```

Run console producer without authorizing user `charlie` (charlie is NOT in group): SHOULD FAIL

```bash
$ docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/charlie.properties << EOF
message Charlie
EOF
```

Result:

```
[2019-10-09 16:12:34,995] WARN [Producer clientId=console-producer] Error while fetching metadata with correlation id 1 : {testtopic=TOPIC_AUTHORIZATION_FAILED} (org.apache.kafka.clients.NetworkClient)
[2019-10-09 16:12:35,001] ERROR [Producer clientId=console-producer] Topic authorization failed for topics [testtopic] (org.apache.kafka.clients.Metadata)
[2019-10-09 16:12:35,003] ERROR Error when sending message to topic testtopic with key: null, value: 15 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.TopicAuthorizationException: Not authorized to access topics: [testtopic]
```


For reference, listing ACLs:

```bash
$ docker container exec broker kafka-acls --bootstrap-server broker:9092 --list --command-config /service/kafka/users/kafka.properties

Current ACLs for resource `ResourcePattern(resourceType=GROUP, name=test-consumer-group, patternType=LITERAL)`:
        (principal=Group:Kafka Developers, host=*, operation=ALL, permissionType=ALLOW)

Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=testtopic, patternType=LITERAL)`:
        (principal=Group:Kafka Developers, host=*, operation=CREATE, permissionType=ALLOW)
        (principal=Group:Kafka Developers, host=*, operation=WRITE, permissionType=ALLOW)
        (principal=Group:Kafka Developers, host=*, operation=DESCRIBE, permissionType=ALLOW)
        (principal=Group:Kafka Developers, host=*, operation=ALL, permissionType=ALLOW)
```

## Credits

Largely inspired by [Dabz/kafka-security-playbook](https://github.com/Dabz/kafka-security-playbook/tree/master/ldap)