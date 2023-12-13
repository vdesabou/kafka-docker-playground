# Schema Validation on Confluent Server

## Objective

Quickly test [Schema Validation on Confluent Server](https://docs.confluent.io/platform/current/schema-registry/schema-validation.html#sv-on-cs).


## How to run

Simply run:

```
$ playground run -f 2way-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f 2way-ssl-and-security-plugin<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Schema Registry is configured at broker level:

```yml
  broker:
    environment:
      KAFKA_CONFLUENT_SCHEMA_REGISTRY_URL: "https://schema-registry:8081"
      KAFKA_CONFLUENT_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.client.truststore.jks
      KAFKA_CONFLUENT_SSL_TRUSTSTORE_PASSWORD: confluent
      KAFKA_CONFLUENT_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.client.keystore.jks
      KAFKA_CONFLUENT_SSL_KEYSTORE_PASSWORD: confluent
      KAFKA_CONFLUENT_SSL_KEY_PASSWORD: confluent
      # for 2way-ssl-and-security-plugin.sh
      KAFKA_CONFLUENT_BASIC_AUTH_CREDENTIALS_SOURCE: USER_INFO
      KAFKA_CONFLUENT_BASIC_AUTH_USER_INFO: 'read:read'
```

Create topic topic-validation:

```bash
$ docker exec broker kafka-topics --bootstrap-server broker:9092 --create --topic topic-validation --partitions 1 --replication-factor 2 --command-config /etc/kafka/secrets/client_without_interceptors.config --config confluent.key.schema.validation=true --config confluent.value.schema.validation=true
```

Describe topic:

```bash
$ docker exec broker kafka-topics \
   --describe \
   --topic topic-validation \
   --bootstrap-server broker:9092 \
   --command-config /etc/kafka/secrets/client_without_interceptors.config
```

Register schema:

```bash
$ curl -X POST \
   -H "Content-Type: application/vnd.schemaregistry.v1+json" \
   --cert ../../environment/2way-ssl/security/connect.certificate.pem --key ../../environment/2way-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/2way-ssl/security/snakeoil-ca-1.crt \
   --data '{ "schema": "[ { \"type\":\"record\", \"name\":\"user\", \"fields\": [ {\"name\":\"userid\",\"type\":\"long\"}, {\"name\":\"username\",\"type\":\"string\"} ]} ]" }' \
   https://schema-registry:8081/subjects/topic-validation-value/versions
```

Note: for `2way-ssl-and-security-plugin.sh`, we need to use user `write`

Sending a non-Avro record, it should fail:

```bash
$ docker exec -i connect kafka-console-producer \
     --topic topic-validation \
     --broker-list broker:9092 \
     --producer.config /etc/kafka/secrets/client_without_interceptors.config << EOF
{"userid":1,"username":"RODRIGUEZ"}
EOF
```

```
[2021-07-13 05:53:27,612] ERROR Error when sending message to topic topic-validation with key: null, value: 35 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
```

Sending a Avro record, it should work:

```bash
$ docker exec -i connect kafka-avro-console-producer \
     --topic topic-validation \
     --broker-list broker:9092 \
     --property schema.registry.url=https://schema-registry:8081 \
     --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks \
     --property schema.registry.ssl.truststore.password=confluent \
     --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks \
     --property schema.registry.ssl.keystore.password=confluent \
     --property value.schema='{"type":"record","name":"user","fields":[{"name":"userid","type":"long"},{"name":"username","type":"string"}]}' \
     --producer.config /etc/kafka/secrets/client_without_interceptors.config << EOF
{"userid":1,"username":"RODRIGUEZ"}
EOF
```

Note: for `2way-ssl-and-security-plugin.sh`, we need to use user `write`:

```bash
$ docker exec -i connect kafka-avro-console-producer \
     --topic topic-validation \
     --broker-list broker:9092 \
     --property basic.auth.credentials.source=USER_INFO \
     --property schema.registry.basic.auth.user.info="write:write" \
     --property schema.registry.url=https://schema-registry:8081 \
     --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks \
     --property schema.registry.ssl.truststore.password=confluent \
     --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks \
     --property schema.registry.ssl.keystore.password=confluent \
     --property value.schema='{"type":"record","name":"user","fields":[{"name":"userid","type":"long"},{"name":"username","type":"string"}]}' \
     --producer.config /etc/kafka/secrets/client_without_interceptors.config << EOF
{"userid":1,"username":"RODRIGUEZ"}
EOF
```