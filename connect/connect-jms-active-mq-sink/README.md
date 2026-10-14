# JMS ActiveMQ Sink connector

## Objective

Quickly test the [JMS Sink](https://docs.confluent.io/kafka-connectors/jms-sink/current/overview.html) connector with ActiveMQ, using the ActiveMQ Docker [image](https://hub.docker.com/r/rmohr/activemq/) and the `activemq-all` 5.15.4 client.

## Prerequisites

With CP 8.x, the JMS Sink connector version must be 2.1.16 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-active-mq-sink.sh
```

| Script | Description |
| --- | --- |
| `jms-active-mq-sink.sh` | JMS sink writing to ActiveMQ queue `DEV.QUEUE.1` |

The ActiveMQ UI is reachable at [http://127.0.0.1:8161](http://127.0.0.1:8161) (`admin`/`admin`).

## What the script does

1. Downloads `activemq-all-5.15.4.jar` if needed and copies it into the JMS Sink connector `lib` folder.
2. Starts ActiveMQ alongside the plaintext environment.
3. Produces the message `This is my message` to topic `sink-messages` with `playground topic produce`.
4. Creates the `jms-active-mq-sink` connector (`java.naming.provider.url=tcp://activemq:61616`, `jms.destination.type=queue`, `jms.destination.name=DEV.QUEUE.1`, String converters).
5. Reads a message from queue `DEV.QUEUE.1` through the ActiveMQ REST API (`http://localhost:8161/api/message/DEV.QUEUE.1?type=queue`) and checks that it is `This is my message`.
