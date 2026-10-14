# Lenses JMS Source connector

## Objective

Quickly test the [Lenses JMS Source](https://docs.lenses.io/3.0/connectors/source/jms.html#activemq-setup) connector (Stream Reactor) with ActiveMQ.

The example uses the ActiveMQ docker [image](https://hub.docker.com/r/rmohr/activemq/).

## Prerequisites

Not supported with the `cfk` environment.

## How to run

```bash
playground run -f lenses-active-mq-source.sh
```

`--connector-tag` sets the Stream Reactor release (default `1.2.3`): the script downloads `kafka-connect-jms-<version>-2.1.0-all.tar.gz` from the [stream-reactor releases](https://github.com/lensesio/stream-reactor/releases).

## What the script does

1. Downloads `activemq-all-5.15.4.jar` and the Lenses JMS connector release.
2. Starts the environment with an ActiveMQ container.
3. Creates the Lenses JMS source connector `lenses-active-mq-source` with KCQL `INSERT INTO MyKafkaTopicName SELECT * FROM myqueue WITHTYPE QUEUE` and `JsonSimpleConverter`.
4. Sends a JSON message to JMS queue `myqueue` through the ActiveMQ REST API (`http://localhost:8161/api/message/myqueue`).
5. Verifies that topic `MyKafkaTopicName` receives the message with `playground topic consume`.
