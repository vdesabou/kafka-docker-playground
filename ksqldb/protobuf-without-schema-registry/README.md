# How to use Protobuf without Schema Registry

## Objective

An example of Protobufs without Schema Registry.
With ksqlDb 0.27, we introduced a new serialization format that allows working with Protocol Buffer messages without Schema Registry: **PROTOBUF_NOSR**.

This complements the existing PROTOBUF format, which does require Schema Registry. Given an existing topic of Protobuf-serialized records, it’s no longer necessary to reprocess data upstream to allow ksqlDB to process it, because the new format does not rely on a Schema Registry schema ID in the serialized bytes.

When leveraging PROTOBUF_NOSR, the data is simply raw Protobuf messages serialized into bytes, so they can be produced and consumed by clients in any language Protobuf supports.

## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
- https://www.confluent.io/blog/announcing-ksqldb-0-27-1/#protobufs-without-schema-registry
- Using example from https://github.com/rootcss/python-kafka-protobuf-events
