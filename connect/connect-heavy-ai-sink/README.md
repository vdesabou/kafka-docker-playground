# HEAVY-AI (Formerly OmniSci) Sink connector

## Objective

Quickly test the [HEAVY-AI (Formerly OmniSci) Sink](https://docs.confluent.io/kafka-connect-heavy-ai/current/overview.html) connector.

## Prerequisites

With CP 8.0+, connector version 1.0.9 or later is required (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f heavy-ai-sink.sh
```

| Script | Description |
| --- | --- |
| `heavy-ai-sink.sh` | Basic example, against a local OmniSci container |

## What the script does

1. Starts the environment with an `omnisci` container.
2. Produces 3 Avro records (`id`, `product`, `quantity`, `price`) to topic `orders`.
3. Creates the `omnisci-sink` connector with `auto.create=true`.
4. Verifies the rows with `select * from orders;` using `omnisql` in the `omnisci` container.
