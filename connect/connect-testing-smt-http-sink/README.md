# Testing Single Message Transforms (SMTs) — HTTP Sink carrier

This example verifies that the **Confluent-provided SMTs** (`confluentinc/connect-transforms`,
package `io.confluent.connect.transforms.*`) keep working across Confluent Platform versions,
using the self-managed **HTTP Sink** connector as the carrier.

Unlike the Apache Kafka built-in SMTs (`org.apache.kafka.connect.transforms.*`, shipped on the
Connect runtime classpath), the Confluent SMTs are a Confluent Hub component and must be on the
plugin path. KDP installs any component listed in `CONNECT_PLUGIN_PATH`, so
`docker-compose.plaintext.yml` lists both the HTTP sink connector and
`confluentinc-connect-transforms`.

Each SMT is its own script so CI reports a pass/fail per SMT. All scripts here share the same
`docker-compose.plaintext.yml`. SMTs that need a different carrier connector (e.g. routing SMTs
such as `ExtractTopic` / `MessageTimestampRouter`) live in their own `connect-testing-smt-<connector>`
folder.

Records are produced, the SMT is applied, and the connector POSTs to a controllable mock HTTP
server (reused from `connect-http-sink`). The transformed payload is verified by inspecting the
body received by the mock server.

## Scenarios

- `replacefield.sh` — `ReplaceField` (`io.confluent.connect.transforms.ReplaceField$Value`):
  renames field `email` → `email_address` and verifies the renamed field in the received body.
- `filter.sh` — `Filter` (`io.confluent.connect.transforms.Filter$Value`): produces `keep` and
  `drop` category records and keeps only those matching the JSONPath `filter.condition`
  (`include`), verifying only the kept records reach the HTTP server.
- `tombstonehandler.sh` — `TombstoneHandler` (`io.confluent.connect.transforms.TombstoneHandler`):
  produces regular + tombstone records with `behavior: ignore`, verifying the tombstones are
  dropped and only regular records reach the HTTP server.
- `drop.sh` — `Drop` (`io.confluent.connect.transforms.Drop$Key`): smoke test that nullifies the
  record key; verifies the connector runs and all records still flow to the HTTP server.

SMTs that need a different carrier or special input are covered elsewhere:
`GzipDecompress` (needs gzip-compressed byte values) and the routing SMTs `ExtractTopic` /
`MessageTimestampRouter` (need a topic-aware carrier).
