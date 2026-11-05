# C/C++ client (librdkafka) (producer/consumer)

## Objective

Quickly test the [Confluent C/C++ Client for Apache Kafka](https://docs.confluent.io/kafka-clients/librdkafka/current/overview.html) ([librdkafka](https://github.com/confluentinc/librdkafka), the library the Python, Go, .NET and JavaScript clients are built on) against a local Confluent Platform cluster, with a producer and a consumer written in C.

librdkafka has no Schema Registry serializer: this example only produces and consumes string records (Avro with Schema Registry in C needs [libserdes](https://github.com/confluentinc/libserdes), out of scope here).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | C producer and consumer, string records, in the `client-c` container, against the plaintext broker |

## What the script does

1. Starts only the `client-c` container and what it depends on (broker), with `playground start-environment --service client-c`. The image is built from the `Dockerfile`: librdkafka from the [Confluent clients apt repository](https://packages.confluent.io/clients/deb) (latest 2.x for Debian 12), and [`client.c`](client.c) compiled with `gcc -std=c11 -Wall -Wextra -Werror ... -lrdkafka`. The client prints the librdkafka version (`rd_kafka_version_str()`) at startup, and reads its configuration from [`client.properties`](client.properties), mounted in `/tmp/client.properties`: one [librdkafka property](https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md) per line, set with `rd_kafka_conf_set` (an unknown property is an error).
2. Creates topic `c-string` with 3 partitions.
3. Produces 10 records (key `key-<i>`, value `{"count":<i>}`) with `acks=all`, prints one line per delivery report, and fails if a record was not delivered:

   ```bash
   playground container exec -c client-c --command "client produce c-string /tmp/client.properties 10"
   ```

4. Consumes them with group `c-string-group` (`auto.offset.reset=earliest`, `enable.auto.commit=false`, synchronous `rd_kafka_commit_message` after each record, `rd_kafka_consumer_close` at the end). The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-c --command "client consume c-string /tmp/client.properties 10"
   ```

5. Shows the committed offsets of the group with `playground consumer-group describe --group c-string-group`.

To try your own client code or configuration, edit `client.c` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed). [ccloud/client-c](../../ccloud/client-c/) uses the same image against Confluent Cloud.

## Use another client version

Set `CLIENT_VERSION` to build the image with another librdkafka version than the default, `2.16.0` (`DEFAULT_CLIENT_VERSION` in the `Dockerfile`, packages `librdkafka1` / `librdkafka-dev` of the Confluent apt repository):

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
playground run -f start.sh --client-version 2.10.1   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. It is passed as a build argument by `docker-compose.plaintext.yml`. An old version may not support everything the example uses (the Avro serializer API changed over time).
