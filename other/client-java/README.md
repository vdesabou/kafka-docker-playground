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
| `start-lab.sh` | single-file Java programs of [`labs/`](labs/) (`java X.java`) in a JDK `client-java` container, against the plaintext broker |

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

## Use another client version

Set `CLIENT_VERSION` to build the image with another kafka-clients version than the default, the `kafka.version` of `pom.xml` (`-Dkafka.version` in the build when set). `kafka-avro-serializer` follows with the Confluent Platform release of that Apache Kafka version: the `confluent.version` of `pom.xml` for 4.x, `7.N.0` for 3.N, `6.0.0`-`6.2.0` for 2.6-2.8, `5.N.0` for 2.0-2.5 (the 8.x serializer needs kafka-clients 4.x):

```bash
CLIENT_VERSION=3.9.1 playground run -f start.sh
playground run -f start.sh --client-version 3.9.1   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. It is passed as a build argument by `docker-compose.plaintext.yml`. An old version may not support everything the example uses (the Avro serializer API changed over time).

## Run single-file programs (`start-lab.sh`)

```bash
playground run -f start-lab.sh
TAG=7.9.10 CLIENT_VERSION=3.9.1 playground run -f start-lab.sh   # another CP version (ZooKeeper mode) and client version
```

`start-lab.sh` uses `docker-compose.plaintext.lab.yml` instead of `docker-compose.plaintext.yml`. The image is built from the `lab` target of the same `Dockerfile`: a JDK (`eclipse-temurin:21-jdk`) instead of the JRE, the client jars of the build (`mvn dependency:copy-dependencies`, so `CLIENT_VERSION` works the same way) in `/usr/share/java/kafka` with `CONFLUENT_HOME=/usr` like in the Confluent Platform images, `procps` (`ps`, `pkill`), and log4j2 as the logging backend of the clients like in the Confluent Platform 8 images (`log4j-api`, `log4j-core`, `log4j-slf4j2-impl`; the `slf4j-simple` of the fat jar is left out), so `-Dlog4j2.configurationFile=<file>` works. The [`labs/`](labs/) folder is mounted in `/app/labs`, the working directory, so a program edited on the host runs at once, without a rebuild. The container depends on the broker only (no Schema Registry); in ZooKeeper mode (CP 7.x) the script starts the `zookeeper` service too.

1. Starts the `client-java` lab container and the broker with `playground start-environment --service client-java`.
2. Creates topic `orders` with 3 partitions.
3. Runs [`ProducerBasics.java`](labs/ProducerBasics.java), which sends 5 records and prints the partition and offset of each, and fails if one of them is not acknowledged:

   ```bash
   playground container exec -c client-java --command "java -cp \"\$CONFLUENT_HOME/share/java/kafka/*\" ProducerBasics.java broker:9092"
   ```

4. Reads them back with [`LabConsumer.java`](labs/LabConsumer.java) (group `lab-check`, it stops on its own after 20 seconds, INFO logs with [`labs/log4j2.xml`](labs/log4j2.xml)), and fails if fewer than 5 records come back:

   ```bash
   playground container exec -c client-java --command "java -Dlog4j2.configurationFile=log4j2.xml -cp \"\$CONFLUENT_HOME/share/java/kafka/*\" LabConsumer.java bootstrap.servers=broker:9092 group.id=lab-check x.topic=orders x.run.ms=20000"
   ```

5. Shows the committed offsets of group `lab-check` with `playground consumer-group describe`.

The other programs and their arguments are listed in [`labs/README.md`](labs/README.md). The lab image is named `client-java-lab` and is rebuilt at each start (`pull_policy: build`, cached layers), so it never replaces the fat jar image of `start.sh`.
