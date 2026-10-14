# Prometheus Sink connector

## Objective

Quickly test the [Prometheus Metrics Sink](https://docs.confluent.io/kafka-connectors/prometheus-metrics/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimum supported connector version is 2.0.4 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f prometheus-sink.sh
```

Prometheus is reachable at [http://localhost:19090](http://localhost:19090).

## What the script does

1. Starts the environment with a Prometheus server scraping the connector endpoint `connect:8889`.
2. Creates the Prometheus metrics sink connector `prometheus-sink` (`prometheus.listener.url=http://connect:8889/metrics`, `behavior.on.error=LOG`).
3. Produces 6 Avro gauge metrics (`kafka_gaugeMetric1` to `kafka_gaugeMetric6`) to topic `test-topic` with `playground topic produce`.
4. Waits for the connector to consume all records with `playground connector show-lag`.
5. Verifies that metric `kafka_gaugeMetric1` is available with the Prometheus query API (skipped on CI).

Example of result for `curl 'http://localhost:19090/api/v1/query?query=kafka_gaugeMetric1'`:

```json
{
    "data": {
        "result": [
            {
                "metric": {
                    "__name__": "kafka_gaugeMetric1",
                    "instance": "connect:8889",
                    "job": "connect-metrics"
                },
                "value": [
                    1585572837.592,
                    "5.639623848362502"
                ]
            }
        ],
        "resultType": "vector"
    },
    "status": "success"
}
```
