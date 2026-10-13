# IBM MQ Sink connector (IBM's own version)

## Objective

Quickly test IBM's own open source [Kafka Connect MQ Sink](https://github.com/ibm-messaging/kafka-connect-mq-sink) connector (`com.ibm.eventstreams.connect.mqsink.MQSinkConnector`), not to be confused with the Confluent [IBM MQ Sink](../connect-ibm-mq-sink) connector.

This connector is not on Confluent Hub. The script downloads `kafka-connect-mq-sink-<version>-jar-with-dependencies.jar` from the [GitHub releases](https://github.com/ibm-messaging/kafka-connect-mq-sink/releases), which is what [building the connector](https://github.com/ibm-messaging/kafka-connect-mq-sink/blob/main/README.md#building-the-connector) (`mvn clean package`) produces. It packages that jar as a Confluent Hub zip (`ibm-messaging-kafka-connect-mq-sink-<version>.zip`) and installs it. The jar already bundles the IBM MQ client, so you don't need to download `IBM-MQ-Install-Java-All.jar`.

Using IBM MQ Docker [image](https://github.com/ibm-messaging/mq-container) `icr.io/ibm-messaging/mq`.

The script:

* produces 3 messages to topic `sink-messages`
* creates the sink connector to queue `DEV.QUEUE.1` of queue manager `QM1`
* checks the 3 messages in the queue with `amqsbcg`

Version 3.0.0 and later need Java 17, so the script skips them (exit code 111) with CP versions older than 8.

## How to run

```bash
playground run -f ibm-messaging-mq-sink<tab>
```

Use `--connector-tag` to choose the connector release (default `3.1.0`):

```bash
playground run -f ibm-messaging-mq-sink<tab> --connector-tag 2.2.1
```

To test a jar that you built locally, package it the same way: put it in the `lib/` folder of a zip with a `manifest.json` (see the script), and pass that zip with `--connector-zip`.
