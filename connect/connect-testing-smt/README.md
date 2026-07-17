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
- `docker-compose.plaintext.datagen.yml` — datagen source only (used by the SMT scripts that need
  to inspect the record key, headers or target topic name by consuming the output topic).
- `docker-compose.plaintext.datagen.transforms.yml` — datagen source + `confluentinc-connect-transforms`
  (used by the Confluent SMT scripts that route on a datagen source).
- `docker-compose.plaintext.debezium-postgres.yml` — Debezium PostgreSQL source (used by the Debezium
  SMT scripts, whose SMTs ship inside the Debezium connector plugin).

## Confluent SMT scenarios (`io.confluent.connect.transforms.*`)

- `replacefield.sh` — `ReplaceField$Value`: renames field `email` → `email_address`.
- `filter.sh` — `Filter$Value`: keeps only records matching the JSONPath `filter.condition`.
- `tombstonehandler.sh` — `TombstoneHandler` (`behavior: ignore`): drops tombstone records.
- `drop.sh` — `Drop$Key`: nullifies the record key (datagen source with the key set from
  `route_field`, verifies the key no longer carries that value on the output topic).
- `flatten-confluent.sh` — `Flatten$Value` (Confluent, distinct from the Apache one): flattens a
  nested structure to `nested.inner`.
- `extracttopic.sh` — `ExtractTopic$Value`: routes records to a topic named after the `route_field`
  value (datagen source, consumes the `ROUTE_FIELD_VALUE` topic).
- `messagetimestamprouter.sh` — `MessageTimestampRouter`: rewrites the topic from a value timestamp
  field (HTTP sink smoke — the SMT requires a schemaless Map value, so a datagen source can't be used).
- `gzipdecompress.sh` — `GzipDecompress$Value`: decompresses a gzip `byte[]` value (kcat produces the
  gzip bytes, HTTP sink with `ByteArrayConverter`; functional check — the SMT needs a real `byte[]`).

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
- `valuetokey.sh` — `ValueToKey`: forms the record key from the `route_field` value field
  (datagen source, verifies the key on the output topic).
- `insertheader.sh` — `InsertHeader`: adds a static header (datagen source, verifies the header).
- `headerfrom.sh` — `HeaderFrom$Value` (`operation: move`): moves `route_field` into a header
  (datagen source, verifies the header).
- `dropheaders.sh` — `DropHeaders`: keeps one inserted header and removes another (datagen source,
  verifies the kept header is present and the dropped one is absent).
- `regexrouter.sh` — `RegexRouter`: rewrites the topic `smt-output` → `smt-output-transformed`
  (datagen source, consumes the renamed topic).
- `timestamprouter.sh` — `TimestampRouter`: rewrites the topic to `<topic>-<yyyyMMdd>` (HTTP sink
  smoke — datagen source records have a null timestamp, which the SMT can't route on).
- `setschemametadata.sh` — `SetSchemaMetadata$Value`: overrides the value schema name/version (datagen
  source with Avro + Schema Registry, verifies the registered schema name on `smt-output-value`).

## Debezium SMT scenarios (`io.debezium.transforms.*`)

- `eventrouter.sh` — `EventRouter` (outbox pattern): Debezium PostgreSQL source; inserting an outbox
  row routes the event to `outbox.event.<aggregatetype>`, verified by consuming `outbox.event.customer`.
- `timezoneconverter.sh` — `TimezoneConverter`: Debezium PostgreSQL source; converts a `timestamptz`
  field to the `+05:30` offset, verified on `dbz.public.tz_test`.
- `TimescaleDb` (`io.debezium.connector.postgresql.transforms.timescaledb.TimescaleDb`) is already
  covered by the existing `connect/connect-debezium-timescaledb-source/debezium-timescaledb-source.sh`
  (needs the TimescaleDB Postgres extension), so it is not duplicated here.
