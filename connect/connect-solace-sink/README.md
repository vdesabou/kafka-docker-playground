# Solace Sink connector

## Objective

Quickly test the [Solace Sink](https://docs.confluent.io/kafka-connectors/solace/sink/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 2.1.16 or later.
* The Solace JMS client `sol-jms-10.6.4.jar` is downloaded from Maven Central on the first run and copied into the connector `lib` folder.

## How to run

```bash
playground run -f solace-sink.sh
```

Solace UI is available at [127.0.0.1:8080](http://127.0.0.1:8080) (`admin`/`admin`).

## What the script does

1. Starts a Solace PubSub+ broker and waits for it to be ready.
2. Produces 10 string records to topic `sink-messages`.
3. Creates the Solace Sink connector writing to the queue `connector-quickstart` (`solace.dynamic.durables=true`) on `smf://solace:55555`.
4. Runs the Solace CLI script `show_queue_cmd` in the `solace` container and checks that the queue holds 10 messages.

The Solace CLI commands in `show_queue_cmd` are:

```
enable
show
queue connector-quickstart
```
