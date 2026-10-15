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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) publishes messages to the MQTT topic of the connector (`mosquitto_pub -l`, with the QoS and credentials of the connector) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), in **steady mode only**: MQTT is publish/subscribe, a paused MQTT source stays subscribed, so the messages published while it is paused go to its in-memory buffer (`records.buffer.queue.size`) or are dropped by the broker, and a drain would not measure MQTT. Once the example is running:

```bash
# throughput during 2 minutes while batches of 20000 messages are published
playground connector benchmark --mode steady --duration 2m --nb-records 20000
```

When the broker publishes more than the connector consumes, mosquitto drops the messages it cannot deliver (`Outgoing messages are being dropped for client ...` in its logs), and the summary warns that the load generated much more than the connector processed.
