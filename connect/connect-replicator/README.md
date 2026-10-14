# Confluent Replicator

## Objective

Quickly test the [Confluent Replicator](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html) connector.

This is just to test security configurations with Replicator, replicating a topic to another topic of the same cluster. More useful examples are [MDC and single views](https://github.com/framiere/mdc-with-replicator-and-regexrouter) and, in this repository, [Replicator as connector](../../multi-data-center/replicator-connect) and [Replicator as executable](../../multi-data-center/replicator-executable).

## Prerequisites

The `sasl-ssl` and `2way-ssl` variants are not supported with the `cfk` environment.

## How to run

```bash
playground run -f replicator.sh
```

| Script | Description |
| --- | --- |
| `replicator.sh` | No security (PLAINTEXT), topic `test-topic` replicated to `test-topic-duplicate` |
| `replicator-sasl-ssl.sh` | SASL_SSL (PLAIN) authentication, using the `sasl-ssl` environment, topic `test-topic-sasl-ssl` replicated to `test-topic-sasl-ssl-duplicate` |
| `replicator-2way-ssl.sh` | SSL (mutual TLS) authentication, using the `2way-ssl` environment, topic `test-topic-ssl` replicated to `test-topic-ssl-duplicate` |

## What the script does

1. Starts the environment (`plaintext` by default, `sasl-ssl` or `2way-ssl` for the secured variants).
2. Produces 10 messages to the source topic with `playground topic produce`.
3. Creates the Replicator connector (`io.confluent.connect.replicator.ReplicatorSourceConnector`) with `topic.whitelist`, `topic.rename.format`, `provenance.header.enable=true` and `ByteArrayConverter` key/value/header converters, `src.kafka.*` and `dest.kafka.*` both pointing to `broker:9092`.
4. Verifies that the destination topic receives 10 messages with `playground topic consume`.

## Security configuration

With security in place, the same client settings must be given to the source cluster (`src.kafka.` prefix), the destination cluster (`dest.kafka.` prefix) and the license topic (`confluent.topic.` prefix).

SASL_SSL (`replicator-sasl-ssl.sh`), shown for `src.kafka.`:

```json
{
    "src.kafka.bootstrap.servers": "broker:9092",
    "src.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
    "src.kafka.ssl.truststore.password" : "confluent",
    "src.kafka.security.protocol" : "SASL_SSL",
    "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
    "src.kafka.sasl.mechanism": "PLAIN"
}
```

2 way SSL (`replicator-2way-ssl.sh`), shown for `src.kafka.`:

```json
{
    "src.kafka.bootstrap.servers": "broker:9092",
    "src.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
    "src.kafka.ssl.keystore.password" : "confluent",
    "src.kafka.ssl.key.password" : "confluent",
    "src.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
    "src.kafka.ssl.truststore.password" : "confluent",
    "src.kafka.security.protocol" : "SSL"
}
```

Use `playground connector show-config` to display the full connector configuration once it is running.
