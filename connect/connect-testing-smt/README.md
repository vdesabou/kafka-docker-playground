# Testing Single Message Transforms (SMTs)

Each script exercises one SMT end-to-end to confirm it keeps working on a new Confluent Platform
or Java version. The carrier connector is only a vehicle to run the SMT; the current scripts use
the self-managed HTTP Sink connector and verify the result from the mock HTTP server body and/or
the `success-responses` topic.

Overrides:

- `docker-compose.plaintext.yml` — HTTP sink + `confluentinc-connect-transforms` (used by the
  Confluent SMT scripts).
- `docker-compose.plaintext.builtin.yml` — HTTP sink only (used by the Apache built-in SMT
  scripts).

## Confluent SMT scenarios (`io.confluent.connect.transforms.*`)

- `replacefield.sh` — `ReplaceField$Value`: renames field `email` → `email_address`.
- `filter.sh` — `Filter$Value`: keeps only records matching the JSONPath `filter.condition`.
- `tombstonehandler.sh` — `TombstoneHandler` (`behavior: ignore`): drops tombstone records.
- `drop.sh` — `Drop$Key`: nullifies the record key.

## Apache built-in SMT scenarios (`org.apache.kafka.connect.transforms.*`)

- `insertfield.sh` — `InsertField$Value`: inserts a static field.
- `maskfield.sh` — `MaskField$Value`: masks the `email` field.
- `hoistfield.sh` — `HoistField$Value`: wraps the value under a `wrapper` field.
- `flatten.sh` — `Flatten$Value`: flattens a nested structure.
- `cast.sh` — `Cast$Value`: casts the `level` field to `int32`.
- `extractfield.sh` — `ExtractField$Value`: extracts a single field as the record value.
- `timestampconverter.sh` — `TimestampConverter$Value`: converts a unix-millis field to a
  formatted date string.
- `replacefield-apache.sh` — `ReplaceField$Value`: renames field `email` → `email_apache`.
- `filter-apache.sh` — `Filter` + `RecordIsTombstone` predicate: drops tombstone records.
- `valuetokey.sh` — `ValueToKey`: forms the record key from the `id` value field.
