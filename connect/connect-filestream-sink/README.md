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
| `filestream-sink-throttled-by-quota.sh` | Throttle the sink with a client quota on the consumer of its task, then remove it |

## What the script does

1. Produces 5 JSON records generated with faker to topic `filestream` with `playground topic produce`.
2. Creates the `filestream-sink` connector (`JsonConverter` without schemas) writing to `/tmp/output.json`.
3. Displays the content of `/tmp/output.json` in the `connect` container with `playground container exec`.

## Throttled by a client quota

`filestream-sink-throttled-by-quota.sh` reproduces a sink connector slowed down by a broker [client quota](https://docs.confluent.io/platform/current/kafka/design.html#quotas), for example a customer sink whose lag grows while its `fetch-throttle-time-avg` metric is above 0:

1. Creates the `filestream-sink` connector (`StringConverter`).
2. Sets a fetch quota of 1 KB/s on the client id of its task (`connector-consumer-filestream-sink-0`) with `playground quota set --connector filestream-sink --consumer-byte-rate 1024`.
3. Produces 100 records of 1 KB, and checks that after 30 seconds only part of them is in `/tmp/output.json`.
4. Removes the quota with `playground quota delete --connector filestream-sink`, and checks that the remaining records are written within 60 seconds.

While it runs, follow the effect with:

```bash
playground quota get                                          # every quota of the cluster
playground connector show-lag --connector filestream-sink     # lag going down slowly
playground get-jmx-metrics -c connect --domain kafka.consumer  # fetch-throttle-time-avg / fetch-throttle-time-max
```

## Benchmark

[`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) replays the `playground topic produce` of the script with `--nb-messages <n>`, so it works for this example (and any sink example) without a load script. Once the example is running:

```bash
# time to write a backlog of 3M records
playground connector benchmark --nb-records 3000000 --interval 2s

# throughput during 2 minutes while records are produced continuously
playground connector benchmark --mode steady --duration 2m
```

The connector is paused while the backlog is produced, then resumed, and the benchmark measures the time it takes to process it. Results are compared with the previous benchmark.
