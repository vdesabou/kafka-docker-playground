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
