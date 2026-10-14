# AppDynamics Metrics sink connector

## Objective

Quickly test the [AppDynamics Metrics sink](https://docs.confluent.io/kafka-connectors/appdynamics-metrics/current/overview.html) connector.

A real AppDynamics Standalone Machine Agent only opens its HTTP metric listener after it registers with an AppDynamics account and Controller, which makes it unsuitable for a self-contained test. Instead, this example runs a small mock of the listener (`docker-appdynamics-metrics/mock-machine-agent.py`) that accepts `POST /api/v1/metrics` and returns HTTP `204`, which is exactly the contract the connector (`AppDClient`) relies on. No AppDynamics account, Controller or licensed machine agent bundle is required.

## How to run

```bash
playground run -f appdynamics-metrics-sink.sh
```

| Script | Description |
| --- | --- |
| `appdynamics-metrics-sink.sh` | AppDynamics Metrics sink connector sending to a mock machine agent |

## What the script does

1. Starts the environment with the `appdynamics-metrics` mock machine agent container (port `8293`).
2. Produces an Avro metric record to `appdynamics-metrics-topic` with `playground topic produce`.
3. Creates the AppDynamics Metrics sink connector pointing at the mock (`machine.agent.host=http://appdynamics-metrics`, `machine.agent.port=8293`).
4. Verifies the connector delivered the metrics by waiting for a `metricName` payload in the mock logs (`playground container logs --container appdynamics-metrics --wait-for-log "metricName"`).
