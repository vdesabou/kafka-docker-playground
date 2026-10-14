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
