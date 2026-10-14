# MQTT Sink connector

## Objective

Quickly test the [MQTT Sink](https://docs.confluent.io/kafka-connectors/mqtt/current/mqtt-sink-connector/overview.html) connector with a Mosquitto broker.

## Prerequisites

With CP 8.x, the minimum supported connector version is 1.7.5 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f mqtt-sink.sh
```

| Script | Description |
| --- | --- |
| `mqtt-sink.sh` | Basic example, `tcp://mosquitto:1883` with username/password |
| `mqtt-sink-mtls.sh` | Same, with mTLS (`ssl://mosquitto:8883`, certificates generated with `playground tools certs-create`) |

## What the script does

1. Starts the environment with a Mosquitto container (`mtls` variant: first generates keystores, truststores and certificates for `connect` and `mosquitto` in `security/`).
2. Produces one message to topic `sink-messages` with `playground topic produce`.
3. Creates the MQTT sink connector (`sink-mqtt` or `sink-mqtt-mtls`), with `mqtt.qos=2`.
4. Verifies with `mosquitto_sub` that the message is received in MQTT topic `sink-messages`.

## Notes

The `password` file was created for user `myuser` (password `mypassword`) with:

```bash
mosquitto_passwd -c password myuser
```
