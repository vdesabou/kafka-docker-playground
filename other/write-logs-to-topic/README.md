# Write Connect logs to a Kafka topic

## Objective

Send the logs of the Kafka Connect worker (runtime and connectors, with their `[connector|task-0]` context) to topic `connect-logs`, in addition to the console, with a log4j appender.

The appender depends on the CP version:

| CP version | Logging | Appender | Configuration |
| --- | --- | --- | --- |
| 8.0 and above (Kafka 4.x) | log4j2 | `Kafka` appender of log4j-core (`org.apache.logging.log4j.core.appender.mom.kafka.KafkaAppender`) | [`log4j2-plaintext.yaml`](log4j2-plaintext.yaml), [`log4j2-sasl-ssl.yaml`](log4j2-sasl-ssl.yaml), [`log4j2-2way-ssl.yaml`](log4j2-2way-ssl.yaml) |
| 7.x and below | log4j 1 | `org.apache.kafka.log4jappender.KafkaLog4jAppender` | [`log4j-plaintext.properties`](log4j-plaintext.properties), [`log4j-sasl-ssl.properties`](log4j-sasl-ssl.properties), [`log4j-2way-ssl.properties`](log4j-2way-ssl.properties) |

⚠️ Kafka 4.0 removed the `kafka-log4j-appender` module, so a CP 7 configuration with `KafkaLog4jAppender` does not work after an upgrade to CP 8: migrate it to the log4j2 `Kafka` appender as below.

⚠️ The CP 7 `cp-server-connect` image doesn't ship the `kafka-log4j-appender` jar either: without it the worker logs `log4j:ERROR Could not instantiate class [org.apache.kafka.log4jappender.KafkaLog4jAppender].` and sends nothing. With CP 7, the scripts download `org.apache.kafka:kafka-log4j-appender:3.9.1` from Maven Central to `kafka-log4j-appender.jar`, mount it, and add it to the worker's `CLASSPATH`. This was verified with CP 7.9.10.

## How to run

```bash
playground run -f start-plaintext<tab>
playground run -f start-sasl-ssl<tab>
playground run -f start-2way-ssl<tab>
playground run -f start-plaintext<tab> --tag 7.9.10    # CP 7: KafkaLog4jAppender
```

## What the scripts do

1. start the environment (`plaintext`, `sasl-ssl` or `2way-ssl`) with the override that matches the CP version: `docker-compose.<environment>.yml` (CP 8+, log4j2) or `docker-compose.<environment>.log4j1.yml` (CP 7, after downloading `kafka-log4j-appender.jar`)
2. wait for at least 10 records in topic `connect-logs`: `playground topic wait-for-records --topic connect-logs --min-expected-messages 10`
3. check that the worker startup log is in the topic: `playground topic consume --topic connect-logs --grep "Kafka Connect started"`

## How it works (CP 8+, log4j2)

The override mounts the log4j2 configuration in the `connect` container and points `KAFKA_LOG4J_OPTS` to it:

```yaml
  connect:
    volumes:
      - ../../other/write-logs-to-topic/log4j2-plaintext.yaml:/tmp/connect/log4j2.yaml
    environment:
      KAFKA_LOG4J_OPTS: "-Dlog4j2.configurationFile=file:/tmp/connect/log4j2.yaml"
```

The `Kafka` appender and the loggers that use it:

```yaml
    Kafka:
      name: KAFKA
      topic: connect-logs
      # record key: the worker host name, to tell the workers apart
      key: "${hostName}"
      # do not block the logging thread on each record
      syncSend: false
      PatternLayout:
        Pattern: "[%d] %p %X{connector.context}%m (%c:%L)"
      Property:
        - name: bootstrap.servers
          value: "broker:9092"
        # fail fast instead of blocking the worker when the broker is unreachable
        - name: max.block.ms
          value: "5000"

  Loggers:
    Logger:
      # Connect runtime and connectors logs (with their connector context) go to the topic too
      - name: org.apache.kafka.connect
        level: INFO
        AppenderRef:
          - ref: KAFKA
      # never send the logs of the producer of the appender to the appender (recursive logging)
      - name: org.apache.kafka.clients
        level: WARN
        additivity: false
        AppenderRef:
          - ref: STDOUT
```

- Each `Property` is a Kafka producer config: add `security.protocol`, `sasl.*` and `ssl.*` for a secured cluster (see [`log4j2-sasl-ssl.yaml`](log4j2-sasl-ssl.yaml) and [`log4j2-2way-ssl.yaml`](log4j2-2way-ssl.yaml)).
- To send only the logs of one connector, use a logger on its package (for example `io.confluent.connect.jdbc`) instead of `org.apache.kafka.connect`.
- A custom `KAFKA_LOG4J_OPTS` replaces the configuration rendered by the image, so the `CONNECT_LOG4J_LOGGERS` and `CONNECT_LOG4J_ROOT_LOGLEVEL` variables no longer apply. `playground debug log-level` still changes the levels at runtime.
- The topic is auto-created by the broker on the first record. Create it beforehand where auto-creation is disabled.
