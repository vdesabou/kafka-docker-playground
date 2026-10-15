# RabbitMQ Source connector

## Objective

Quickly test the [RabbitMQ Source](https://docs.confluent.io/kafka-connectors/rabbitmq-source/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimum supported connector version is 1.8.0 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f rabbitmq-source.sh
```

| Script | Description |
| --- | --- |
| `rabbitmq-source.sh` | Basic example |
| `rabbitmq-source-ssl.sh` | Same, with SSL on port `5671` (`rabbitmq.security.protocol=SSL`, certificates generated with `playground tools certs-create`) |

## What the script does

1. Starts the environment with a RabbitMQ container and Python producer/consumer containers (`ssl` variant: first generates keystores, truststores and certificates for `connect` and `rabbitmq` in `security/`).
2. Sends 5 messages to RabbitMQ queue `myqueue` with the `rabbitmq-producer` container (`python /producer.py myqueue 5`).
3. Creates the RabbitMQ source connector `rabbitmq-source` (queue `myqueue` to topic `rabbitmq`).
4. Verifies that topic `rabbitmq` receives 5 messages with `playground topic consume`.
5. Asserts with `rabbitmqctl list_queues` that queue `myqueue` is empty, i.e. all messages were acknowledged and removed.

Example of records:

```text
"´\u0001{\"id\": 0, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
"´\u0001{\"id\": 1, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
```

## Notes

To consume all records of RabbitMQ queue `myqueue`:

```bash
playground container exec --container rabbitmq-consumer --command "bash -c \"python /consumer.py myqueue\""
```

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) publishes messages to the queue of the connector with the `producer.py` of the example (one connection). With the default `rabbitmq.prefetch.count` (500), a paused connector holds at most 500 messages, the backlog stays in the queue, for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to consume a backlog of 1M messages
playground connector benchmark --nb-records 1000000

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the messages are sent, then resumed, and the benchmark measures the time it takes to consume them.
