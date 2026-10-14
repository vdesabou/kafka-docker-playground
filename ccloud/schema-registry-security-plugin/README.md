# Confluent Schema Registry Security Plugin with Confluent Cloud

## Objective

Quickly test the [Confluent Schema Registry Security Plugin](https://docs.confluent.io/platform/current/confluent-security-plugins/schema-registry/introduction.html) with a self-managed Schema Registry that uses Confluent Cloud as its Kafka store.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Requires CP 6.0 or later (the script exits with code `111` otherwise).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Schema Registry with basic authentication (`JETTY_AUTH`) and the ACL authorizer, storing schemas in the `schemas-security-plugin` topic in Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and deletes the `schemas-security-plugin` topic of a previous run.
2. Starts a local `schema-registry` container with the security plugin (`jaas_config_8_plus.file` is used for CP 8.0+, `jaas_config.file` otherwise; users are defined in `password-file`).
3. Creates ACLs with `sr-acl-cli`: `read` gets `SUBJECT_READ`, `write` gets `SUBJECT_WRITE`, `admin` gets all operations (`GLOBAL_SUBJECTS_READ` is replaced by `GLOBAL_READ` from CP 6.1).
4. Registers the `subject1-value` subject with the `write` user.
5. Lists subjects with the `read` user (expected to fail with `40301`) and with the `admin` user (expected to succeed).
6. Gets the versions of `subject1-value` with the `read` user (expected to succeed).

## Configuration details

Users available on `http://localhost:8081`:

| User:password | Permissions |
| --- | --- |
| `read:read` | Global read access (`SUBJECT_READ`) |
| `write:write` | Global write access (`SUBJECT_WRITE`) |
| `admin:admin` | Global admin access (all operations) |

Schema Registry security plugin configuration:

```yaml
      SCHEMA_REGISTRY_KAFKASTORE_TOPIC: "schemas-security-plugin"
      SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL: "SASL_SSL"
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: $BOOTSTRAP_SERVERS
      SCHEMA_REGISTRY_KAFKASTORE_SASL_JAAS_CONFIG: $SASL_JAAS_CONFIG
      SCHEMA_REGISTRY_KAFKASTORE_SASL_MECHANISM: "PLAIN"
      SCHEMA_REGISTRY_SCHEMA_REGISTRY_RESOURCE_EXTENSION_CLASS: "io.confluent.kafka.schemaregistry.security.SchemaRegistrySecurityResourceExtension"
      SCHEMA_REGISTRY_CONFLUENT_SCHEMA_REGISTRY_AUTHORIZER_CLASS: io.confluent.kafka.schemaregistry.security.authorizer.schemaregistryacl.SchemaRegistryAclAuthorizer
      SCHEMA_REGISTRY_AUTHENTICATION_METHOD: "BASIC"
      SCHEMA_REGISTRY_AUTHENTICATION_ROLES: "write,read,admin"
      SCHEMA_REGISTRY_AUTHENTICATION_REALM: "Schema"
      SCHEMA_REGISTRY_OPTS: "-Djava.security.auth.login.config=$JAAS_CONFIG_FILE"
      SCHEMA_REGISTRY_CONFLUENT_SCHEMA_REGISTRY_AUTH_MECHANISM: "JETTY_AUTH"
```

Expected results:

```bash
curl -X GET -u read:read http://localhost:8081/subjects
# {"error_code":40301,"message":"User is denied operation on this server."}

curl -X GET -u admin:admin http://localhost:8081/subjects
# ["subject1-value"]

curl -X GET -u read:read http://localhost:8081/subjects/subject1-value/versions
# [1]
```
