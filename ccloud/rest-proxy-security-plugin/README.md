# Confluent REST Proxy Security Plugin with Confluent Cloud

## Objective

Quickly test [Principal Propagation](https://docs.confluent.io/platform/current/kafka-rest/production-deployment/rest-proxy/security.html#credentials-propagation) of the REST Proxy Security Plugin with Confluent Cloud.

> [!NOTE]
> The main limitation is that the client SSL certificate must contain the Confluent Cloud API key as DN rather than a username (tracked by FF-1552).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY` | Confluent Cloud API key used as the principal of the HTTP client (also the CN of its certificate) |
| `CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_SECRET` | Secret of that API key |
| `CONFLUENT_LICENSE` | Confluent license, set in `KAFKA_REST_CONFLUENT_LICENSE` (the security plugin is a commercial feature) |

## How to run

```bash
export CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY="<api key>"
export CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_SECRET="<api secret>"
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | REST Proxy with HTTPS + mTLS and the security plugin, connected to Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment (`bootstrap_ccloud_environment`).
2. Generates `kafka-rest.jaas.conf` from `kafka-rest.jaas-template.conf` with the API key and secret.
3. Generates certificates for `restproxy` and for a client whose CN is the API key (`playground tools certs-create`).
4. Starts the `restproxy` container (HTTPS listener on port `8082`, client authentication required, `KafkaRestSecurityResourceExtension`).
5. Creates the `rest-proxy-security-plugin` topic in Confluent Cloud.
6. Produces a JSON record with `curl` over mTLS using the client certificate: the API key is the principal propagated to the Confluent Cloud cluster.

## Configuration details

Security configurations between REST Proxy and HTTP client:

```yaml
      KAFKA_REST_LISTENERS: "https://0.0.0.0:8082"
      KAFKA_REST_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.truststore.jks
      KAFKA_REST_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.restproxy.keystore.jks
      KAFKA_REST_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_REST_SSL_KEY_PASSWORD: confluent
      KAFKA_REST_SSL_ENDPOINT_IDENTIFIED_ALGORITHM: "https"
```

Security configurations between REST Proxy and Confluent Cloud (Kafka and Schema Registry):

```yaml
      KAFKA_REST_CLIENT_SECURITY_PROTOCOL: SASL_SSL
      KAFKA_REST_CLIENT_SASL_MECHANISM: PLAIN
      KAFKA_REST_CLIENT_ENDPOINT_IDENTIFICATION_ALGORITHM: "https"
      KAFKA_REST_CLIENT_SASL_JAAS_CONFIG: $SASL_JAAS_CONFIG

      KAFKA_REST_SCHEMA_REGISTRY_URL: $SCHEMA_REGISTRY_URL
      KAFKA_REST_CLIENT_BASIC_AUTH_CREDENTIALS_SOURCE: USER_INFO
      KAFKA_REST_CLIENT_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO: $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
```

The JAAS file is generated with `CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY` and `CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_SECRET`:

```
KafkaClient {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username=":CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY:"
  password=":CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_SECRET:";
};
```

```yaml
      KAFKAREST_OPTS: -Djava.security.auth.login.config=/etc/kafka/kafka-rest.jaas.conf
```

Security extension configuration:

```yaml
      KAFKA_REST_CONFLUENT_LICENSE: "$CONFLUENT_LICENSE"
      KAFKA_REST_SSL_CLIENT_AUTH: "true" # deprecated, KAFKA_REST_SSL_CLIENT_AUTHENTICATION: "REQUIRED"
      KAFKA_REST_KAFKA_REST_RESOURCE_EXTENSION_CLASS: io.confluent.kafkarest.security.KafkaRestSecurityResourceExtension
      KAFKA_REST_CONFLUENT_REST_AUTH_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=TEST.*$$/$$1/,DEFAULT
```

HTTP client request using the `$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY` principal (run from the `restproxy` container):

```bash
curl -X POST \
  --cert /etc/kafka/secrets/$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY.certificate.pem \
  --key /etc/kafka/secrets/$CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY.key \
  --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -H "Accept: application/vnd.kafka.v2+json" \
  --data '{"records":[{"value":{"foo":"bar"}}]}' \
  "https://localhost:8082/topics/rest-proxy-security-plugin"
```
