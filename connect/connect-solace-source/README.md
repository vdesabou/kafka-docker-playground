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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends messages to the destination of the connector through the REST messaging port of the broker (`curl`, keep-alive, 16 parallel transfers), for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to consume a backlog of 1M messages
playground connector benchmark --nb-records 1000000

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the messages are sent, then resumed, and the benchmark measures the time it takes to consume them. A topic (publish/subscribe) can only be measured with `--mode steady`: a paused subscriber does not keep the backlog in the broker.
