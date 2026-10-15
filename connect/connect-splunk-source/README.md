# Splunk Source connector

## Objective

Quickly test the [Splunk Source](https://docs.confluent.io/kafka-connectors/splunk-source/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 1.1.6 or later.

## How to run

```bash
playground run -f splunk-source.sh
```

## What the script does

1. Generates a keystore for the connector HTTPS listener with `playground tools certs-create` (in `security/`).
2. Creates the Splunk Source connector listening on port `8889` (HTTPS), writing to topic `splunk-source`.
3. Simulates an application sending an event to the HEC-compatible endpoint:

   ```bash
   curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'
   ```

4. Verifies the event with `playground topic consume --topic splunk-source`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends events to the HTTP event collector of the connector (`curl`, 1000 events per request), for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), in **steady mode only**: the connector receives the events itself, and keeps the events sent while it is paused in memory, so a drain would not measure it. Once the example is running:

```bash
# throughput during 2 minutes while batches of 10000 events are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```
