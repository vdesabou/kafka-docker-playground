# Confluent REST Proxy Security Plugin

## Objective

Quickly test [Principal Propagation](https://docs.confluent.io/current/confluent-security-plugins/kafka-rest/principal_propagation.html#principal-propagation).


## How to run

Simply run:

```
$ playground run -f start-sasl-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f start-2way-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f start-sasl-plain-with-basic-auth<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## With SASL

Brokers are configured with SASL_SSL.

Security configurations between REST Proxy and HTTP client

```yml
      # Security configurations between REST Proxy and HTTP client
      KAFKA_REST_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.truststore.jks
      KAFKA_REST_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.keystore.jks
      KAFKA_REST_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEY_PASSWORD: confluent
```

Security configurations between REST Proxy and broker, using `client` principal

```yml
      # Security configurations between REST Proxy and broker
      KAFKA_REST_CLIENT_SECURITY_PROTOCOL: SASL_SSL
      KAFKA_REST_CLIENT_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.truststore.jks
      KAFKA_REST_CLIENT_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_REST_CLIENT_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.keystore.jks
      KAFKA_REST_CLIENT_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_REST_CLIENT_SSL_KEY_PASSWORD: confluent
      KAFKA_REST_CLIENT_SASL_MECHANISM: PLAIN
      KAFKA_REST_CLIENT_ENDPOINT_IDENTIFICATION_ALGORITHM: "https"
      KAFKA_REST_CLIENT_SASL_JAAS_CONFIG: "org.apache.kafka.common.security.plain.PlainLoginModule required \
              username=\"client\" \
              password=\"client-secret\";"

```

JAAS file

```yml
      KAFKAREST_OPTS: -Djava.security.auth.login.config=/etc/kafka/kafka-rest.jaas.conf
```

`clientrestproxy` is the principal used by HTTP client and propagated to broker:

```
KafkaClient {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="clientrestproxy"
  password="clientrestproxy-secret";
};
```

Security extension configuration

```yml
      # Security extension configuration
      KAFKA_REST_SSL_CLIENT_AUTHENTICATION: "REQUIRED"
      KAFKA_REST_KAFKA_REST_RESOURCE_EXTENSION_CLASS: io.confluent.kafkarest.security.KafkaRestSecurityResourceExtension
      KAFKA_REST_CONFLUENT_REST_AUTH_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=TEST.*$$/$$1/,DEFAULT
      KAFKA_REST_CONFLUENT_LICENSE: "your license"
```

HTTP client using `clientrestproxy` principal:

```bash
$ docker exec restproxy curl -X POST --cert /etc/kafka/secrets/clientrestproxy.certificate.pem --key /etc/kafka/secrets/clientrestproxy.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://localhost:8086/topics/jsontest"
```

We can verify principal `clientrestproxy`is used:

```log
[2020-05-12 13:46:43,292] DEBUG Principal = User:clientrestproxy is Allowed Operation = Write from host = 192.168.16.6 on resource = Topic:LITERAL:jsontest (kafka.authorizer.logger)
```

Note: If Confluent REST Proxy Security Plugin is not configured, then principal used would be `client`.


## With 2WAY SSL

Brokers are configured with SSL (2way).

Security configurations between REST Proxy and HTTP client

```yml
      # Security configurations between REST Proxy and HTTP client
      KAFKA_REST_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.truststore.jks
      KAFKA_REST_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.keystore.jks
      KAFKA_REST_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEY_PASSWORD: confluent
```

Important: `/etc/kafka/secrets/kafka.restproxy.keystore.jks` should contain the certificate with private key of the HTTP client principal used `clientrestproxy`, this is done like this:

```bash
$ openssl pkcs12 -export -in clientrestproxy-ca1-signed.crt -inkey clientrestproxy.key \
               -out clientrestproxy.p12 -name clientrestproxy \
               -CAfile snakeoil-ca-1.crt -caname CARoot -passout pass:confluent

$ keytool -importkeystore \
        -deststorepass confluent -destkeypass confluent -destkeystore kafka.restproxy.keystore.jks \
        -srckeystore clientrestproxy.p12 -srcstoretype PKCS12 -srcstorepass confluent \
        -alias clientrestproxy
```

Security configurations between REST Proxy and broker, using `client` principal

```yml
      # Security configurations between REST Proxy and broker
      KAFKA_REST_CLIENT_SECURITY_PROTOCOL: SSL
      KAFKA_REST_CLIENT_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.truststore.jks
      KAFKA_REST_CLIENT_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_REST_CLIENT_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.keystore.jks
      KAFKA_REST_CLIENT_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_REST_CLIENT_SSL_KEY_PASSWORD: confluent
      KAFKA_REST_CLIENT_ENDPOINT_IDENTIFICATION_ALGORITHM: "https"

```

`clientrestproxy` is the principal used by HTTP client and propagated to broker:


Security extension configuration

```yml
      # Security extension configuration
      # ZooKeeper required to validate trial license
      KAFKA_REST_ZOOKEEPER_CONNECT: zookeeper:2181
      # KAFKA_REST_SSL_CLIENT_AUTHENTICATION: "REQUIRED"
      KAFKA_REST_SSL_CLIENT_AUTH: "true" # deprecated, KAFKA_REST_SSL_CLIENT_AUTHENTICATION: "REQUIRED"
      KAFKA_REST_KAFKA_REST_RESOURCE_EXTENSION_CLASS: io.confluent.kafkarest.security.KafkaRestSecurityResourceExtension
```

HTTP client using `clientrestproxy` principal:

```bash
$ docker exec restproxy curl -X POST --cert /etc/kafka/secrets/clientrestproxy.certificate.pem --key /etc/kafka/secrets/clientrestproxy.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://restproxy:8086/topics/jsontest"
```

We can verify principal `clientrestproxy` is used:

```log
[2020-05-14 13:45:58,814] DEBUG Principal = User:clientrestproxy is Allowed Operation = Write from host = 192.168.0.6 on resource = Topic:LITERAL:jsontest (kafka.authorizer.logger)
```

Note: If Confluent REST Proxy Security Plugin is not configured, then principal used would be `restproxy`.

## With HTTP Basic Authentication to SASL Authentication

Broker is configured with SASL_PLAIN, and `clientrestproxy`user has been added:

```yml
  broker:
    environment:
      KAFKA_LOG4J_LOGGERS: "kafka.authorizer.logger=DEBUG"
      KAFKA_AUTHORIZER_CLASS_NAME: $KAFKA_AUTHORIZER_CLASS_NAME
      KAFKA_ALLOW_EVERYONE_IF_NO_ACL_FOUND: "true"
      KAFKA_LISTENER_NAME_BROKER_PLAIN_SASL_JAAS_CONFIG: |
              org.apache.kafka.common.security.plain.PlainLoginModule required \
              username="broker" \
              password="broker" \
              user_broker="broker" \
              user_controlcenter="controlcenter-secret" \
              user_schemaregistry="schemaregistry-secret" \
              user_ksqldb="ksqldb-secret" \
              user_connect="connect-secret" \
              user_sftp="sftp-secret" \
              user_clientrestproxy="clientrestproxy-secret" \
              user_client="client-secret";
```


Security configurations between REST Proxy and broker, using `clientrestproxy` principal

```yml
      # Security configurations between REST Proxy and broker
      # This is required for dub kafka-ready tool only (Docker specific)
      # it can be removed, but in that case KAFKA_OPTS: "-Djava.security.auth.login.config=/etc/kafka/sasl-plain-with-basic-auth.properties"
      # should be set
      KAFKA_REST_CLIENT_SASL_JAAS_CONFIG: "org.apache.kafka.common.security.plain.PlainLoginModule required \
              username=\"clientrestproxy\" \
              password=\"clientrestproxy-secret\";"

```

HTTP Basic Authentication to SASL Authentication:

```yml
      # HTTP Basic Authentication
      # https://docs.confluent.io/platform/current/kafka-rest/production-deployment/rest-proxy/security.html#http-basic-authentication
      KAFKAREST_OPTS: "-Djava.security.auth.login.config=/etc/kafka/sasl-plain-with-basic-auth.properties"
      KAFKA_REST_AUTHENTICATION_METHOD: BASIC
      KAFKA_REST_AUTHENTICATION_REALM: KafkaRest
      KAFKA_REST_AUTHENTICATION_ROLES: thisismyrole
      KAFKA_REST_CONFLUENT_REST_AUTH_PROPAGATE_METHOD: JETTY_AUTH
```

where `sasl-plain-with-basic-auth.properties` contains:

```properties
KafkaRest {
    org.eclipse.jetty.jaas.spi.PropertyFileLoginModule required
    debug="true"
    file="/tmp/password.properties";
};

KafkaClient {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="clientrestproxy"
  password="clientrestproxy-secret";
};
```

and `password.properties`:

```properties
clientrestproxy: clientrestproxy-secret,thisismyrole
```

curl command is using `clientrestproxy` principal:

```
docker exec --privileged --user root restproxy curl -X POST -u clientrestproxy:clientrestproxy-secret -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "http://localhost:8086/topics/jsontest"
```


