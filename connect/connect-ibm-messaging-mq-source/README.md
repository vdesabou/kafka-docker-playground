# IBM MQ Source connector (IBM's own version)

## Objective

Quickly test IBM's own open source [Kafka Connect MQ Source](https://github.com/ibm-messaging/kafka-connect-mq-source) connector (`com.ibm.eventstreams.connect.mqsource.MQSourceConnector`), not to be confused with the Confluent [IBM MQ Source](../connect-ibm-mq-source) connector.

This connector is not on Confluent Hub. The script downloads `kafka-connect-mq-source-<version>-jar-with-dependencies.jar` from the [GitHub releases](https://github.com/ibm-messaging/kafka-connect-mq-source/releases) (the jar that [building the connector](https://github.com/ibm-messaging/kafka-connect-mq-source/blob/main/README.md#building-the-connector) with `mvn clean package` produces), packages it as a Confluent Hub zip (`ibm-messaging-kafka-connect-mq-source-<version>.zip`) and installs it. The jar already bundles the IBM MQ client, so `IBM-MQ-Install-Java-All.jar` is not needed.

IBM MQ runs with the Docker [image](https://github.com/ibm-messaging/mq-container) `icr.io/ibm-messaging/mq`.

## Prerequisites

Connector versions 3.0.0 and later need Java 17: the script skips them (exit code 111) with CP versions older than 8.

## How to run

```bash
playground run -f ibm-messaging-mq-source.sh
```

Use `--connector-tag` to choose the connector release (default `3.0.0`):

```bash
playground run -f ibm-messaging-mq-source.sh --connector-tag 2.8.1
```

To test a jar that you built locally, package it the same way (jar in the `lib/` folder of a zip with a `manifest.json`, see the script) and pass that zip with `--connector-zip`.

| Script | Description |
| --- | --- |
| `ibm-messaging-mq-source.sh` | Source from queue `DEV.QUEUE.1` of queue manager `QM1` to topic `MyKafkaTopicName` |

## What the script does

1. Downloads the connector jar from GitHub and packages it as a Confluent Hub zip (unless `--connector-zip` is used).
2. Starts the environment with an IBM MQ container (`ibmmq`).
3. Creates the `ibm-messaging-mq-source` connector from queue `DEV.QUEUE.1` (channel `DEV.APP.SVRCONN`, user `app`, `mq.message.body.jms=true`) to topic `MyKafkaTopicName`.
4. Puts 2 messages in the queue with `amqsput`.
5. Verifies the 2 records with `playground topic consume --topic MyKafkaTopicName`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) puts messages in the queue of the connector (`amqsput`, after raising the max depth of the queue, which is 5000 by default), for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to consume a backlog of 1M messages
playground connector benchmark --nb-records 1000000

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the messages are sent, then resumed, and the benchmark measures the time it takes to consume them.
