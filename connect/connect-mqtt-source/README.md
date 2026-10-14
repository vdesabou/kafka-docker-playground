# MQTT Source connector

## Objective

Quickly test the [MQTT Source](https://docs.confluent.io/kafka-connectors/mqtt/current/mqtt-source-connector/overview.html) connector with a Mosquitto broker.

## Prerequisites

With CP 8.x, the minimum supported connector version is 1.7.5 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f mqtt-source.sh
```

| Script | Description |
| --- | --- |
| `mqtt-source.sh` | Basic example, `tcp://mosquitto:1883` with username/password |
| `mqtt-source-mtls.sh` | Same, with mTLS (`ssl://mosquitto:8883`, certificates generated with `playground tools certs-create`) |

## What the script does

1. Starts the environment with a Mosquitto container (`mtls` variant: first generates keystores, truststores and certificates for `connect` and `mosquitto` in `security/`).
2. Creates the MQTT source connector `source-mqtt` (MQTT topic `my-mqtt-topic` to Kafka topic `mqtt-source-1`, `mqtt.qos=2`).
3. Publishes message `sample-msg-1` to MQTT topic `my-mqtt-topic` with `mosquitto_pub`.
4. Verifies that topic `mqtt-source-1` receives the message with `playground topic consume`.

## Notes

The `password` file was created for user `myuser` (password `mypassword`) with:

```bash
mosquitto_passwd -c password myuser
```
