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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends messages to the ActiveMQ destination of the KCQL of the connector (`FROM <destination> WITHTYPE QUEUE`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), with the JMS producer of the playground (`tools/benchmark-jms`) in the `activemq` container: JSON messages with the fields of the message of the example (`{"u_name": "benchmark message <i>", "u_price": 2.75, "u_quantity": 3}`), since the KCQL parses them with `JsonSimpleConverter` and the schema registered for the topic must stay compatible. A paused connector does not consume, so the messages wait in the queue and a drain measures the connector. Once the example is running:

```bash
# JMS transactions of 1000 messages
playground connector benchmark --nb-records 10000

# one persistent send per message
playground connector benchmark --nb-records 10000 --shape small-txn

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

With `WITHTYPE TOPIC`, a paused subscriber does not keep the messages: use `--mode steady`.

The connector of the example (stream-reactor JMS 1.2.3) reads about 100 messages per second here: start with a small `--nb-records`, or raise `--max-wait`.
