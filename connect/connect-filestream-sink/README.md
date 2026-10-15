# FileStream Sink connector

## Objective

Quickly test the [FileStream Sink](https://docs.confluent.io/platform/current/connect/filestream_connector.html) connector.

## How to run

```bash
playground run -f filestream-sink.sh
```

| Script | Description |
| --- | --- |
| `filestream-sink.sh` | Sink JSON records from a topic to a file in the `connect` container |

## What the script does

1. Produces 5 JSON records generated with faker to topic `filestream` with `playground topic produce`.
2. Creates the `filestream-sink` connector (`JsonConverter` without schemas) writing to `/tmp/output.json`.
3. Displays the content of `/tmp/output.json` in the `connect` container with `playground container exec`.

## Benchmark

[`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) replays the `playground topic produce` of the script with `--nb-messages <n>`, so it works for this example (and any sink example) without a load script. Once the example is running:

```bash
# time to write a backlog of 3M records
playground connector benchmark --nb-records 3000000 --interval 2s

# throughput during 2 minutes while records are produced continuously
playground connector benchmark --mode steady --duration 2m
```

The connector is paused while the backlog is produced, then resumed, and the benchmark measures the time it takes to process it. Results are compared with the previous benchmark.
