# Confluent Schema Registry Security Plugin with Confluent Cloud

## Objective

Quickly test [Confluent Schema Registry Security Plugin](https://docs.confluent.io/current/confluent-security-plugins/schema-registry/introduction.html#sr-security-plugin) with Confluent Cloud.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

## How to run


Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Details of what the script is doing


Confluent Schema Registry Security Plugin is configured with `JETTY_AUTH`

```yml
  schema-registry:
    image: ${CP_SCHEMA_REGISTRY_IMAGE}:${TAG}
    hostname: schema-registry
    container_name: schema-registry
    ports:
      - '8081:8081'
    environment:
      CUB_CLASSPATH: '/etc/confluent/docker/docker-utils.jar:/usr/share/java/cp-base-new/*:/usr/share/java/confluent-security/schema-registry/*:/usr/share/java/schema-registry/*'
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8081
      SCHEMA_REGISTRY_KAFKASTORE_TOPIC: "schemas-security-plugin"
      SCHEMA_REGISTRY_KAFKASTORE_SSL_ENDPOINT_IDENTIFIED_ALGORITHM: "https"
      SCHEMA_REGISTRY_KAFKASTORE_REQUEST_TIMEOUT_MS: 20000
      SCHEMA_REGISTRY_KAFKASTORE_RETRY_BACKOFF_MS: 500
      SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL: "SASL_SSL"
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: $BOOTSTRAP_SERVERS
      SCHEMA_REGISTRY_KAFKASTORE_SASL_JAAS_CONFIG: $SASL_JAAS_CONFIG
      SCHEMA_REGISTRY_KAFKASTORE_SASL_MECHANISM: "PLAIN"
      SCHEMA_REGISTRY_SCHEMA_REGISTRY_RESOURCE_EXTENSION_CLASS: "io.confluent.kafka.schemaregistry.security.SchemaRegistrySecurityResourceExtension"
      SCHEMA_REGISTRY_CONFLUENT_SCHEMA_REGISTRY_AUTHORIZER_CLASS: io.confluent.kafka.schemaregistry.security.authorizer.schemaregistryacl.SchemaRegistryAclAuthorizer
      SCHEMA_REGISTRY_AUTHENTICATION_METHOD: "BASIC"
      SCHEMA_REGISTRY_AUTHENTICATION_ROLES: "write,read,admin"
      SCHEMA_REGISTRY_AUTHENTICATION_REALM: "Schema"
      SCHEMA_REGISTRY_OPTS: "-Djava.security.auth.login.config=/tmp/jaas_config.file"
      SCHEMA_REGISTRY_CONFLUENT_SCHEMA_REGISTRY_AUTH_MECHANISM: "JETTY_AUTH"
    volumes:
      - ./jaas_config.file:/tmp/jaas_config.file
      - ./password-file:/tmp/password-file
```

Setting up ACL authorization:

```bash
$ docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p read -o SUBJECT_READ
$ docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p write -o SUBJECT_WRITE
$ docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p admin -o '*'
```

Schema Registry is listening on http://localhost:8081

```
-> user:password  |  description
-> _____________
-> read:read    |  Global read access (SUBJECT_READ)
-> write:write  |  Global write access (SUBJECT_WRITE)
-> admin:admin  |  Global admin access (All operations)
```

Registering a subject with `write` user

```bash
$ curl -X POST -u write:write http://localhost:8081/subjects/subject1-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\n    \"fields\": [\n      {\n        \"name\": \"id\",\n        \"type\": \"long\"\n      },\n      {\n        \"default\": null,\n        \"name\": \"first_name\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"last_name\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"email\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"gender\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"ip_address\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"last_login\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"account_balance\",\n        \"type\": [\n          \"null\",\n          {\n            \"logicalType\": \"decimal\",\n            \"precision\": 64,\n            \"scale\": 2,\n            \"type\": \"bytes\"\n          }\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"country\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"favorite_color\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      }\n    ],\n    \"name\": \"User\",\n    \"namespace\": \"com.example.users\",\n    \"type\": \"record\"\n  }"
}'
{"id":1}
```

Doing an admin operation with `read` user - expected to fail

```bash
$ curl -X GET -u read:read http://localhost:8081/subjects
{"error_code":40301,"message":"User is denied operation on this server."}
```

Doing an admin operation with `admin` user - expected to succeed

```bash
$ curl -X GET -u admin:admin http://localhost:8081/subjects
["subject1-value"]
```

Getting a subject with `read` user - expected to succeed

```bash
$ curl -X GET -u read:read http://localhost:8081/subjects/subject1-value/versions
[1]
```