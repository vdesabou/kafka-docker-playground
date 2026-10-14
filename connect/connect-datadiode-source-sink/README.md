# Data Diode (Source & Sink) connector

## Objective

Quickly test the [Data Diode (Source & Sink)](https://docs.confluent.io/kafka-connectors/data-diode/current/index.html) connector.

## Prerequisites

With CP 8.x, the minimal supported connector version is 1.2.8 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f datadiode.sh
```

| Script | Description |
| --- | --- |
| `datadiode.sh` | Data Diode sink sends records over UDP to a Data Diode source running in the same Connect worker |

## What the script does

1. Creates the `datadiode-source` connector, listening on port `3456` and writing to topics prefixed with `dest_` (encrypted with a password and salt).
2. Creates the `datadiode-sink` connector, reading topic `diode` and sending records to `connect:3456`.
3. Produces 10 string messages to topic `diode` with `playground topic produce`.
4. Verifies that the 10 messages arrived in topic `dest_diode` with `playground topic consume`.
