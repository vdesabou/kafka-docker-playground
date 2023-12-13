# How to use Protobuf without Schema Registry

## Objective

An example of Protobufs without Schema Registry.
With ksqlDb 0.27, we introduced a new serialization format that allows working with Protocol Buffer messages without Schema Registry: **PROTOBUF_NOSR**.

This complements the existing PROTOBUF format, which does require Schema Registry. Given an existing topic of Protobuf-serialized records, it’s no longer necessary to reprocess data upstream to allow ksqlDB to process it, because the new format does not rely on a Schema Registry schema ID in the serialized bytes.

When leveraging PROTOBUF_NOSR, the data is simply raw Protobuf messages serialized into bytes, so they can be produced and consumed by clients in any language Protobuf supports.

We can create a stream with `PROTOBUF_NOSR`:
```
CREATE STREAM persons (key INT KEY, name STRING, id INT, email STRING, phones ARRAY<STRUCT<number STRING, type INT>>) with (kafka_topic='persons', partitions=1, value_format='PROTOBUF_NOSR');
```

And we can convert this Stream to a Schema Registry aware format (i.e: Avro, Protobuf, JSON_SR):
```
CREATE STREAM persons_protobuf_sr
  WITH (kafka_topic='persons_with_sr', partitions=1, value_format='protobuf')
  AS SELECT * FROM persons;
```

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Resources
- https://www.confluent.io/blog/announcing-ksqldb-0-27-1/#protobufs-without-schema-registry
- Using example from https://github.com/rootcss/python-kafka-protobuf-events
