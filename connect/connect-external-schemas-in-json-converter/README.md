# KIP-1054: Support external schemas in JSONConverter

## Objective

Quickly test [KIP-1054: Support external schemas in JSONConverter](https://cwiki.apache.org/confluence/display/KAFKA/KIP-1054%3A+Support+external+schemas+in+JSONConverter), using the FileStream Sink connector.

## Prerequisites

CP 8.2 or later is required (support for the `value.converter.schema.content` configuration property). The script fails otherwise.

## How to run

```bash
playground run -f filestream-sink-external-schemas-in-json-converter.sh
```

| Script | Description |
| --- | --- |
| `filestream-sink-external-schemas-in-json-converter.sh` | FileStream sink using `JsonConverter` with an external schema set in `value.converter.schema.content` |

## What the script does

1. Produces one schemaless JSON record (`{"id": "emp_001", "name": "Kevin"}`) to topic `filestream` with `playground topic produce`.
2. Creates the `filestream-sink` connector with `value.converter.schemas.enable=true` and the Connect schema provided in `value.converter.schema.content`.
3. Verifies the content of `/tmp/output.json` in the `connect` container, expected to be `Struct{id=emp_001,name=Kevin}`.
