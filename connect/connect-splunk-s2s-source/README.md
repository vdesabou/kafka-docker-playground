# Splunk S2S Source connector

## Objective

Quickly test the [Splunk S2S Source](https://docs.confluent.io/kafka-connectors/splunk-s2s/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 2.2.2 or later.

## How to run

```bash
playground run -f splunk-s2s-source.sh
```

| Script | Description |
| --- | --- |
| `splunk-s2s-source.sh` | Basic example |
| `splunk-s2s-source-ack-support.sh` | With acknowledgments (`splunk.s2s.enable.ack=true` on the connector, `useACK = true` on the Universal Forwarder); checks there are no duplicate events |

## What the script does

1. Creates the Splunk S2S Source connector listening on port `9997`, writing to topic `splunk-s2s-events` (schemaless JSON).
2. Writes a log file with 3 events to the Splunk Universal Forwarder container (`splunk-uf`).
3. Configures the forwarder to monitor the file (`splunk add monitor`) and to forward to `connect:9997` (`splunk add forward-server`).
4. Verifies the events with `playground topic consume --topic splunk-s2s-events`.

Example record:

```json
{"event":"log event 1","time":1625495323,"host":"splunk-uf","source":"/opt/splunkforwarder/splunk-s2s-test.log","index":"default","sourcetype":"splunk-s2s-test-too_small"}
```
