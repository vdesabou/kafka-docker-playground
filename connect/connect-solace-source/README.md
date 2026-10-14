# Solace Source connector

## Objective

Quickly test the [Solace Source](https://docs.confluent.io/kafka-connectors/solace/source/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 1.2.0 or later.
* The Solace JMS client `sol-jms-10.6.4.jar` is downloaded from Maven Central on the first run.

## How to run

```bash
playground run -f solace-source.sh
```

Solace UI is available at [127.0.0.1:8080](http://127.0.0.1:8080) (`admin`/`admin`).

## What the script does

1. Starts a Solace PubSub+ broker and waits for it to be ready.
2. Creates the queue `connector-quickstart` in the `default` Message VPN with the Solace CLI script `create_queue_cmd` (this could also be done in the Solace UI).
3. Creates topic `from-solace-messages` with `message.timestamp.type=LogAppendTime` (to avoid `CreateTime:0` timestamps).
4. Publishes 3 messages to the queue with the Solace REST endpoint (`http://localhost:9000/Queue/connector-quickstart`).
5. Creates the Solace Source connector reading the queue and writing to `from-solace-messages`.
6. Verifies 3 records with `playground topic consume --topic from-solace-messages`.
7. Checks with the SEMP v2 monitoring API that the queue is empty, i.e. messages were acknowledged and deleted by the connector.

The Solace CLI commands in `create_queue_cmd` are:

```
enable
configure
message-spool message-vpn default
create queue connector-quickstart
permission all consume
no shutdown full
```
