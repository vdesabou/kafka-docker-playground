# Confluent REST Proxy Security Plugin with Confluent Cloud

## Objective

Quickly test [Principal Propagation](https://docs.confluent.io/platform/current/kafka-rest/production-deployment/rest-proxy/security.html#credentials-propagation) with Confluent Cloud.

N.B: the main problem at this time is that the SSL certificate would need to include the ccloud key as DN within the certificate rather than a username (tracked by FF-1552)

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)
## How to run


Simply run:

```
$ just use <playground run> command and search for start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY> .sh in this folder
```

## Details of what the script is doing


Security configurations between REST Proxy and HTTP client

```yml
      KAFKA_REST_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.truststore.jks
      KAFKA_REST_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.keystore.jks
      KAFKA_REST_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEY_PASSWORD: confluent
      KAFKA_REST_SSL_ENDPOINT_IDENTIFIED_ALGORITHM: "https"
```

Security configurations between REST Proxy and Confluent Cloud cluster

```yml
      # Security configurations between REST Proxy and broker
      KAFKA_REST_CLIENT_SECURITY_PROTOCOL: SASL_SSL
      KAFKA_REST_CLIENT_SASL_MECHANISM: PLAIN
      KAFKA_REST_CLIENT_ENDPOINT_IDENTIFICATION_ALGORITHM: "https"
      KAFKA_REST_CLIENT_SASL_JAAS_CONFIG: $SASL_JAAS_CONFIG

      # Security configurations between REST Proxy and CCSR
      KAFKA_REST_SCHEMA_REGISTRY_URL: $SCHEMA_REGISTRY_URL
      KAFKA_REST_CLIENT_BASIC_AUTH_CREDENTIALS_SOURCE: USER_INFO
      KAFKA_REST_CLIENT_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO: $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO

```

JAAS file is generated CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY and CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_SECRET passed as argument or environment variables.

```
KafkaClient {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username=":CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY:"
  password=":CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_SECRET:";
};
```

```yml
      KAFKAREST_OPTS: -Djava.security.auth.login.config=/etc/kafka/kafka-rest.jaas.conf
```

`CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY` is the principal used by HTTP client and propagated to broker:

Security extension configuration

```yml
      # Security extension configuration
      KAFKA_REST_CONFLUENT_LICENSE: "your license"
      # KAFKA_REST_SSL_CLIENT_AUTHENTICATION: "REQUIRED"
      KAFKA_REST_SSL_CLIENT_AUTH: "true" # deprecated, KAFKA_REST_SSL_CLIENT_AUTHENTICATION: "REQUIRED"
      KAFKA_REST_KAFKA_REST_RESOURCE_EXTENSION_CLASS: io.confluent.kafkarest.security.KafkaRestSecurityResourceExtension
      KAFKA_REST_CONFLUENT_REST_AUTH_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=TEST.*$$/$$1/,DEFAULT
```

Important: you need to set your license

HTTP client using `$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY` principal:

```bash
$ docker exec -e CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY=$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY restproxy curl -X POST --cert /etc/kafka/secrets/$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY.certificate.pem --key /etc/kafka/secrets/$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://localhost:8086/topics/rest-proxy-security-plugin"
```
