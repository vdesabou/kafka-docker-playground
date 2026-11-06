# ksqlDB JSON_SR: required fields, default values and null

## Objective

Show what a JSON Schema (`JSON_SR`) producer accepts when a field is optional, required, or required with a default value, and how ksqlDB reads the topics.

| Topic | JSON Schema of `stringField` | `{"stringField":"foo"}` | `{"stringField":null}` | `{}` |
| --- | --- | --- | --- | --- |
| `play-json-single` | `"type": "string"` | ✅ | | |
| `play-json-single-required` | `"type": "string"`, required | ✅ | ❌ refused | |
| `play-json-single-default` | `"type": "string"`, `"default": "test"`, required | ✅ | ❌ refused | ❌ refused |

The serializer validates each record against the JSON Schema before sending it:

- `null` is not a `string`, whether the field is required or not: allow it with `"type": ["string", "null"]`
- a `default` does not make a missing required field valid: the validator does not fill in defaults

A refused record never reaches the topic: the producer fails with `SerializationException: Validation error in JSON` (`#/stringField: expected type: String, found: Null`).

## How to run

```bash
playground run -f start<tab>
```

## What the script does

1. creates the 3 topics and registers their JSON Schemas (`playground schema register`)
2. produces the valid records, and checks that the 3 invalid ones are refused by the serializer
3. creates a ksqlDB stream on `play-json-single` with `VALUE_FORMAT = 'JSON_SR'`
