# Couchbase Source connector

## Objective

Quickly test the [Couchbase Source](https://docs.couchbase.com/kafka-connector/current/index.html) connector.

## How to run

```bash
playground run -f couchbase-source.sh
```

| Script | Description |
| --- | --- |
| `couchbase-source.sh` | Stream the `travel-sample` bucket of a local Couchbase server to a Kafka topic |

Couchbase UI is available at [127.0.0.1:8091](http://127.0.0.1:8091) (`Administrator`/`password`).

## What the script does

1. Initializes the Couchbase cluster with `couchbase-cli`.
2. Installs the `travel-sample` sample bucket through the Couchbase REST API and waits (up to 120s) until it is ready.
3. Creates the `couchbase-source` connector (`DefaultSchemaSourceHandler`, `AllPassFilter`, `couchbase.stream.from=SAVED_OFFSET_OR_BEGINNING`) writing to topic `test-travel-sample`.
4. Verifies the topic with `playground topic consume --topic test-travel-sample --min-expected-messages 2`.

Example of record:

```json
{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574178029849280512,
    "content": {
        "bytes": "{\"activity\":\"buy\",\"city\":\"London\",\"country\":\"United Kingdom\",\"id\":16320,\"name\":\"Gabriel's Wharf\",\"type\":\"landmark\", ...}"
    },
    "event": "mutation",
    "expiration": {
        "int": 0
    },
    "flags": {
        "int": 33554432
    },
    "key": "landmark_16320",
    "lockTime": {
        "int": 0
    },
    "partition": 0,
    "revSeqno": 1,
    "vBucketUuid": {
        "long": 259802932746954
    }
}
```
