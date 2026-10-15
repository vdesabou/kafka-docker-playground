# JMS ActiveMQ Source connector

## Objective

Quickly test the [JMS Source](https://docs.confluent.io/kafka-connectors/jms-source/current/overview.html) connector with ActiveMQ, using the ActiveMQ Docker [image](https://hub.docker.com/r/rmohr/activemq/) and the `activemq-all` 5.15.4 client.

## Prerequisites

With CP 8.x, the JMS Source connector version must be 12.2.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-active-mq-source.sh
```

| Script | Description |
| --- | --- |
| `jms-active-mq-source.sh` | JMS source reading from ActiveMQ queue `DEV.QUEUE.1` |

The ActiveMQ UI is reachable at [http://127.0.0.1:8161](http://127.0.0.1:8161) (`admin`/`admin`).

## What the script does

1. Downloads `activemq-all-5.15.4.jar` if needed and copies it into the JMS connector `lib` folder.
2. Starts ActiveMQ alongside the plaintext environment.
3. Creates the `jms-active-mq-source` connector (`java.naming.provider.url=tcp://activemq:61616`, queue `DEV.QUEUE.1`, `kafka.topic=MyKafkaTopicName`).
4. Sends a message to queue `DEV.QUEUE.1` through the ActiveMQ REST API.
5. Verifies that the record lands in topic `MyKafkaTopicName` with `playground topic consume`.
6. Checks through the ActiveMQ admin API that queue `DEV.QUEUE.1` is empty, i.e. the connector acknowledged and removed the message (`commitRecord`).

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends messages to the destination of the connector with `BenchmarkJmsProducer` (`tools/benchmark-jms`), run in the `activemq` container with the `activemq-all` jar of the broker (transactions of 1000 messages), for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to consume a backlog of 1M messages
playground connector benchmark --nb-records 1000000

# same with one persistent send per message instead of transactions of 1000
playground connector benchmark --nb-records 100000 --shape small-txn

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the messages are sent, then resumed, and the benchmark measures the time it takes to consume them. A topic (publish/subscribe) can only be measured with `--mode steady`: a paused subscriber does not keep the backlog in the broker.
