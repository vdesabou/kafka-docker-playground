# IBM MQ Source connector (IBM's own version)

## Objective

Quickly test IBM's own open source [Kafka Connect MQ Source](https://github.com/ibm-messaging/kafka-connect-mq-source) connector (`com.ibm.eventstreams.connect.mqsource.MQSourceConnector`), not to be confused with the Confluent [IBM MQ Source](../connect-ibm-mq-source) connector.

This connector is not on Confluent Hub. The script downloads `kafka-connect-mq-source-<version>-jar-with-dependencies.jar` from the [GitHub releases](https://github.com/ibm-messaging/kafka-connect-mq-source/releases), which is what [building the connector](https://github.com/ibm-messaging/kafka-connect-mq-source/blob/main/README.md#building-the-connector) (`mvn clean package`) produces. It packages that jar as a Confluent Hub zip (`ibm-messaging-kafka-connect-mq-source-<version>.zip`) and installs it. The jar already bundles the IBM MQ client, so you don't need to download `IBM-MQ-Install-Java-All.jar`.

Using IBM MQ Docker [image](https://github.com/ibm-messaging/mq-container) `icr.io/ibm-messaging/mq`.

The script:

* creates the source connector from queue `DEV.QUEUE.1` of queue manager `QM1` to topic `MyKafkaTopicName`
* puts 2 messages in the queue with `amqsput`
* consumes the 2 records from topic `MyKafkaTopicName`

Version 3.0.0 and later need Java 17, so the script skips them (exit code 111) with CP versions older than 8.

## How to run

```bash
playground run -f ibm-messaging-mq-source<tab>
```

Use `--connector-tag` to choose the connector release (default `3.0.0`):

```bash
playground run -f ibm-messaging-mq-source<tab> --connector-tag 2.8.1
```

To test a jar that you built locally, package it the same way: put it in the `lib/` folder of a zip with a `manifest.json` (see the script), and pass that zip with `--connector-zip`.
