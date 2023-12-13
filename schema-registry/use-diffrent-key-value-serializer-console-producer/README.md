# How to use different Key and Value serializer with kafka-avro-console-producer

## Objective

When using kafka-avro-console-producer the default behavior is to produce both the key and value with an Avro serializer

With using ``--property key.serializer=`` in the command you can change the key serializer to use a different format.

For example:
```
kafka-avro-console-producer --bootstrap-server <broker-hostname>:<port> \
--property schema.registry.url=https://<schema-registry-hostname>:<port> \
--property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' \
--producer.config /<path>/<to>/producer.properties \
--topic String-Key-Topic \
--property parse.key=true --property key.separator=":"
--property key.serializer=org.apache.kafka.common.serialization.StringSerializer

"test-key":{"f1": "value1"}
```

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Resources
