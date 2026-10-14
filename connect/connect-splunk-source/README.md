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
