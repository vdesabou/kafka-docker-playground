# Splunk Sink connector

## Objective

Quickly test the [Splunk Sink](https://docs.confluent.io/kafka-connect-splunk-sink/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 2.2.0 or later.

## How to run

```bash
playground run -f splunk-sink.sh
```

Splunk UI is available at [127.0.0.1:8000](http://127.0.0.1:8000) (`admin`/`password`).

| Script | Description |
| --- | --- |
| `splunk-sink.sh` | JSON records sent as raw events (`JsonConverter`, schemaless) |
| `splunk-sink-formatted.sh` | Records already in HEC event format (`splunk.hec.json.event.formatted=true`, `StringConverter`), with indexed fields |

## What the script does

1. Starts a Splunk container and waits for it to be ready.
2. Produces 3 JSON records to topic `splunk-qs`.
3. Creates the Splunk Sink connector sending to the HEC endpoint `http://splunk:8088`, index `main`.
4. Waits 80 seconds, then runs a `splunk search` in the `splunk` container and checks the events are indexed.

The HEC token `99582090-3ac3-4db1-9487-e17b17a05081` comes from `default.yml`:

```yaml
hec_token: 99582090-3ac3-4db1-9487-e17b17a05081
```

## Known issues

* `splunk-sink-formatted.sh`: multi-valued indexed fields (e.g. `"cust_id":["000013935","000013936"]`) require a fix for [splunk/kafka-connect-splunk#444](https://github.com/splunk/kafka-connect-splunk/issues/444), so that case is commented out in the script.
