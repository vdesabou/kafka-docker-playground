#!/usr/bin/env python3
# Confluent Python client (confluent-kafka, on librdkafka): string and Avro producer / consumer.
#
# usage: client.py produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]
#
# The config file has one librdkafka property per line (bootstrap.servers, security.protocol, sasl.*...), plus the
# schema.registry.* properties of the Schema Registry client (schema.registry.url, schema.registry.basic.auth.user.info).

import importlib.metadata
import sys
import time

import confluent_kafka
from confluent_kafka import Consumer, Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

CONSUME_TIMEOUT_SECONDS = 60

PAYMENT_SCHEMA = """
{
  "type": "record",
  "name": "Payment",
  "namespace": "io.confluent.playground",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "amount", "type": "double"}
  ]
}
"""

USAGE = "usage: client.py produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]"


def load_config(path):
    """librdkafka properties, and the schema.registry.* ones for SchemaRegistryClient (prefix removed)."""
    client_conf = {}
    schema_registry_conf = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key, value = key.strip(), value.strip()
            if key.startswith("schema.registry."):
                schema_registry_conf[key[len("schema.registry."):]] = value
            else:
                client_conf[key] = value
    # SchemaRegistryClient has no basic.auth.credentials.source: basic.auth.user.info is enough
    schema_registry_conf.pop("basic.auth.credentials.source", None)
    return client_conf, schema_registry_conf


def produce(topic, client_conf, nb_messages, value_serializer=None):
    producer = Producer({**client_conf, "acks": "all"})
    delivered = 0
    failed = 0

    def on_delivery(err, msg):
        nonlocal delivered, failed
        if err is not None:
            failed += 1
            print(f"Failed to deliver record: {err}", file=sys.stderr)
        else:
            delivered += 1
            print(f"Produced record to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}")

    for i in range(nb_messages):
        key = f"key-{i}"
        if value_serializer is None:
            value = f'{{"id":"{key}","amount":{i * 10.5}}}'
        else:
            value = value_serializer(
                {"id": key, "amount": i * 10.5}, SerializationContext(topic, MessageField.VALUE)
            )
        producer.produce(topic, key=key, value=value, on_delivery=on_delivery)
        producer.poll(0)

    remaining = producer.flush(30)
    if remaining > 0 or failed > 0 or delivered != nb_messages:
        print(f"Only {delivered} records out of {nb_messages} were delivered ({failed} failed, {remaining} still in queue)",
              file=sys.stderr)
        sys.exit(1)
    print(f"{delivered} records were produced to topic {topic}")


def consume(topic, client_conf, nb_messages, value_deserializer=None):
    group = f"{topic}-group"
    consumer = Consumer({
        **client_conf,
        "group.id": group,
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
    })
    consumer.subscribe([topic])
    consumed = 0
    deadline = time.monotonic() + CONSUME_TIMEOUT_SECONDS
    try:
        while consumed < nb_messages:
            if time.monotonic() > deadline:
                print(f"Timeout: consumed {consumed} records out of {nb_messages} after {CONSUME_TIMEOUT_SECONDS}s",
                      file=sys.stderr)
                sys.exit(1)
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print(f"Consumer error: {msg.error()}", file=sys.stderr)
                continue
            key = msg.key().decode("utf-8") if msg.key() is not None else None
            if value_deserializer is None:
                value = msg.value().decode("utf-8") if msg.value() is not None else None
            else:
                value = value_deserializer(msg.value(), SerializationContext(topic, MessageField.VALUE))
            print(f"Consumed record from {msg.topic()} [{msg.partition()}] at offset {msg.offset()}: key={key} value={value}")
            consumer.commit(message=msg, asynchronous=False)
            consumed += 1
    finally:
        # leave the group now: without close(), the member stays in the group until its session times out
        consumer.close()
    print(f"{consumed} records were consumed from topic {topic} by group {group}")


def main():
    if len(sys.argv) < 4 or len(sys.argv) > 5:
        print(USAGE, file=sys.stderr)
        sys.exit(1)
    mode, topic, config_file = sys.argv[1], sys.argv[2], sys.argv[3]
    nb_messages = int(sys.argv[4]) if len(sys.argv) == 5 else 10

    print(f"confluent-kafka {importlib.metadata.version('confluent-kafka')}, librdkafka {confluent_kafka.libversion()[0]}")
    client_conf, schema_registry_conf = load_config(config_file)

    if mode == "produce":
        produce(topic, client_conf, nb_messages)
    elif mode == "consume":
        consume(topic, client_conf, nb_messages)
    elif mode in ("produce-avro", "consume-avro"):
        if "url" not in schema_registry_conf:
            print(f"schema.registry.url is missing in {config_file}", file=sys.stderr)
            sys.exit(1)
        schema_registry_client = SchemaRegistryClient(schema_registry_conf)
        if mode == "produce-avro":
            produce(topic, client_conf, nb_messages, AvroSerializer(schema_registry_client, PAYMENT_SCHEMA))
        else:
            consume(topic, client_conf, nb_messages, AvroDeserializer(schema_registry_client))
    else:
        print(USAGE, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
