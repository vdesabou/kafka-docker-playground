# RabbitMQ Sink connector

## Objective

Quickly test the [RabbitMQ Sink](https://docs.confluent.io/kafka-connectors/rabbitmq-sink/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimum supported connector version is 1.8.0 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f rabbitmq-sink.sh
```

| Script | Description |
| --- | --- |
| `rabbitmq-sink.sh` | Basic example |
| `rabbitmq-sink-ssl.sh` | Same, with SSL on port `5671` (`rabbitmq.security.protocol=SSL`, certificates generated with `playground tools certs-create`) |

## What the script does

1. Starts the environment with a RabbitMQ container (`ssl` variant: first generates keystores, truststores and certificates for `connect` and `rabbitmq` in `security/`).
2. Creates exchange `exchange1` (direct), queue `queue1` and a binding with routing key `rkey1` with `rabbitmqadmin`.
3. Produces 10 messages to topic `rabbitmq-messages` with `playground topic produce`.
4. Creates the RabbitMQ sink connector `rabbitmq-sink` (exchange `exchange1`, routing key `rkey1`, `PERSISTENT` delivery mode).
5. Waits for the connector to consume all records with `playground connector show-lag`, then verifies with `rabbitmqadmin get queue=queue1` that the messages are in the queue.

Example of result:

```text
+-------------+-----------+---------------+---------+---------------+------------------+-------------+
| routing_key | exchange  | message_count | payload | payload_bytes | payload_encoding | redelivered |
+-------------+-----------+---------------+---------+---------------+------------------+-------------+
| rkey1       | exchange1 | 9             | 1       | 1             | string           | False       |
| rkey1       | exchange1 | 8             | 2       | 1             | string           | False       |
...
| rkey1       | exchange1 | 0             | 10      | 2             | string           | False       |
+-------------+-----------+---------------+---------+---------------+------------------+-------------+
```
