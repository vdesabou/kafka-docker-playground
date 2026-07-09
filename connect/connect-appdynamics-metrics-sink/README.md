# AppDynamics Metrics sink connector

## Objective

Quickly test [AppDynamics Metrics sink](https://docs.confluent.io/current/connect/kafka-connect-appdynamics-metrics/index.html) connector.

A real AppDynamics Standalone Machine Agent only opens its HTTP metric listener
after it registers with an AppDynamics account and Controller, which makes it
unsuitable for a self-contained test. Instead this test runs a small mock of the
listener (`docker-appdynamics-metrics/mock-machine-agent.py`) that accepts
`POST /api/v1/metrics` and returns HTTP `204` — exactly the contract the
connector (`AppDClient`) relies on. No AppDynamics account, Controller, or
licensed machine-agent bundle is required.

## How to run

Simply run:

```
$ just use <playground run> command and search for appdynamics-metrics-sink.sh in this folder
```

## Details of what the script is doing

The test produces a metric record to `appdynamics-metrics-topic`, creates the
sink connector pointing at the mock machine agent (`http://appdynamics-metrics:8293`),
and verifies the connector delivered the metrics by asserting the mock received a
non-empty `POST /api/v1/metrics`.

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
