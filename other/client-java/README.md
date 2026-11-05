# Java client (producer/consumer)

## Objective

Quickly test the [Apache Kafka Java client](https://docs.confluent.io/kafka-clients/java/current/overview.html) ([`org.apache.kafka:kafka-clients`](https://central.sonatype.com/artifact/org.apache.kafka/kafka-clients)) and the Confluent Avro serializer for Schema Registry ([`io.confluent:kafka-avro-serializer`](https://packages.confluent.io/maven/io/confluent/kafka-avro-serializer/)) against a local Confluent Platform cluster.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Java producer and consumer, string and Avro records, in the `client-java` container, against the plaintext broker and Schema Registry |

## What the script does

1. Starts only the `client-java` container and what it depends on (broker, Schema Registry), with `playground start-environment --service client-java`. The image is built from the `Dockerfile` (Java 21, Maven fat jar of [`ClientJava.java`](src/main/java/io/confluent/examples/ClientJava.java) with `kafka-clients` 4.4.0 and `kafka-avro-serializer` 8.4.0 from [`pom.xml`](pom.xml)). The client reads its configuration from [`client.properties`](client.properties), mounted in `/tmp/client.properties`: Java client properties, plus the `schema.registry.*` properties of the Avro serializer and deserializer.
2. Creates topics `java-string` and `java-avro` with 3 partitions.
3. Produces 10 string records (key `key-<i>`, value `{"count":<i>}`) with `acks=all` and waits for every acknowledgement, then consumes them with group `java-string-group` (`enable.auto.commit=false`, `commitSync()` after each batch, `close()` at the end). The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-java --command "java -jar client-java.jar produce java-string /tmp/client.properties 10"
   playground container exec -c client-java --command "java -jar client-java.jar consume java-string /tmp/client.properties 10"
   ```

4. Same with Avro records (`GenericRecord` of schema `io.confluent.examples.Payment` with fields `id` and `amount`): `KafkaAvroSerializer` registers the schema under subject `java-avro-value`, `KafkaAvroDeserializer` reads it back:

   ```bash
   playground container exec -c client-java --command "java -jar client-java.jar produce-avro java-avro /tmp/client.properties 10"
   playground container exec -c client-java --command "java -jar client-java.jar consume-avro java-avro /tmp/client.properties 10"
   ```

5. Shows the schema registered under subject `java-avro-value` with `playground schema get`, and the committed offsets of both groups with `playground consumer-group describe`.

The client logs warnings and errors only (`src/main/resources/simplelogger.properties`). To try your own client code or configuration, edit `ClientJava.java` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed). [ccloud/client-java](../../ccloud/client-java/) uses the same image against Confluent Cloud.
