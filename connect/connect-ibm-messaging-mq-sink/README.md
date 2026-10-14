# IBM MQ Sink connector (IBM's own version)

## Objective

Quickly test IBM's own open source [Kafka Connect MQ Sink](https://github.com/ibm-messaging/kafka-connect-mq-sink) connector (`com.ibm.eventstreams.connect.mqsink.MQSinkConnector`), not to be confused with the Confluent [IBM MQ Sink](../connect-ibm-mq-sink) connector.

This connector is not on Confluent Hub. The script downloads `kafka-connect-mq-sink-<version>-jar-with-dependencies.jar` from the [GitHub releases](https://github.com/ibm-messaging/kafka-connect-mq-sink/releases) (the jar that [building the connector](https://github.com/ibm-messaging/kafka-connect-mq-sink/blob/main/README.md#building-the-connector) with `mvn clean package` produces), packages it as a Confluent Hub zip (`ibm-messaging-kafka-connect-mq-sink-<version>.zip`) and installs it. The jar already bundles the IBM MQ client, so `IBM-MQ-Install-Java-All.jar` is not needed.

IBM MQ runs with the Docker [image](https://github.com/ibm-messaging/mq-container) `icr.io/ibm-messaging/mq`.

## Prerequisites

Connector versions 3.0.0 and later need Java 17: the script skips them (exit code 111) with CP versions older than 8.

## How to run

```bash
playground run -f ibm-messaging-mq-sink.sh
```

Use `--connector-tag` to choose the connector release (default `3.1.0`):

```bash
playground run -f ibm-messaging-mq-sink.sh --connector-tag 2.2.1
```

To test a jar that you built locally, package it the same way (jar in the `lib/` folder of a zip with a `manifest.json`, see the script) and pass that zip with `--connector-zip`.

| Script | Description |
| --- | --- |
| `ibm-messaging-mq-sink.sh` | Sink from topic `sink-messages` to queue `DEV.QUEUE.1` of queue manager `QM1` |

## What the script does

1. Downloads the connector jar from GitHub and packages it as a Confluent Hub zip (unless `--connector-zip` is used).
2. Starts the environment with an IBM MQ container (`ibmmq`).
3. Produces 3 messages to topic `sink-messages`.
4. Creates the `ibm-messaging-mq-sink` connector to queue `DEV.QUEUE.1` (channel `DEV.APP.SVRCONN`, user `app`).
5. Verifies the 3 messages are in the queue with `amqsbcg`.
