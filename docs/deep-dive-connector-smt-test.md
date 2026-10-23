# 🍪 Deep dive: `playground connector smt test`

The command that answers "what does this transform chain do to a record?" without creating a topic or a connector: it
runs the `transforms.*` and `predicates.*` of a config on one record, **step by step**, and shows what each step
changed (topic, key, value, headers, schema field by field), which predicate matched, the step that dropped the record,
or the step that threw with its config and its error. Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [🔀 What does this transform chain do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record)
> first. This page goes further: how the command works under the hood, its gotchas, a hands-on lab and recipes for
> support repros.

| You want | Command |
| --- | --- |
| the chain of a config, on a record of your own | `playground connector smt test --record '<json>' < config.json` |
| the chain of a running connector | `playground connector smt test --connector <c>` (`--record`, or a default record) |
| a real record of a topic, through the connector's converters | `… --from-topic <t> --offset N [--partition P]` |
| the same chain on several CP versions | `… --cp-version 7.9.0 --cp-version 8.3.2` |
| an SMT that is not in the worker | `… --smt-plugin confluentinc/connect-transforms:1.6.2` / `--smt-jar my-smt.jar` |
| a source record instead of a sink one | `… --type source` |
| the steps as data | `… --json` |
| the stack trace of the failing step | `… --verbose` |

---

## 1. Mental model (the 3 things to remember)

1. **It runs the worker's own classes, in the worker.** A small Java harness (`SmtTester`) is compiled once for the
   Kafka jars of the image, copied into the running `connect` container, and started with the **classpath and the
   `plugin.path` of the worker JVM** (read from `/proc/1/cmdline`). So the transforms, predicates and converters are
   the same classes and versions as the ones your connector runs, including the plugins installed in the worker. Each
   step prints where its class came from (`from`), and warns when the same class exists in several plugins
   (`also in … the worker could load another copy`), a classic cause of "it works on my worker".

2. **It's the `TransformationChain`, replayed one step at a time.** Like Connect, for each alias of `transforms`:
   configure the transform, test its `predicate` (inverted by `negate`), skip it when it doesn't apply, otherwise
   `apply()`. Three ways a step can end the chain:
   - it returns `null`: `🗑️ dropped by step N` (a `Filter`, a predicate-driven drop): **exit 0**, that's a result.
   - it throws: `❌ the chain stopped at step N`, with the error chain (`--verbose` or `--json` for the stack trace):
     **exit 1**.
   - the record can't even be built (bad `--record`, no record at that offset): **exit 2**.

   A step that changes nothing prints `(no change)`: that's how you spot a **silent no-op** (a `ReplaceField` with a
   typo in the field name), which Connect never reports.

3. **The record is what the connector would see, not what's in Kafka.** With `--record`, you give the Connect data
   directly: schemaless JSON, or `{"schema": …, "payload": …}` (the JsonConverter envelope) for a `Struct`. With
   `--from-topic`, the harness reads the raw bytes at that offset and converts them with the **connector's converters**
   (`key.converter`, `value.converter`, `header.converter`, falling back to the worker's), so an Avro / Protobuf / JSON
   Schema record comes out as the same `Struct` the task would get. A sink record is built by default (`--type source`
   for a source record, the type of `--connector` when given).

---

## 2. The chain and the record

```bash
# chain from stdin (a whole connector config is fine: only transforms.*, predicates.* and converters are used)
playground connector smt test --record '{"topic":"orders","key":"k1","value":{"id":1,"name":"foo"}}' < connector.json

# chain from a file, record from a file
playground connector smt test --config @connector.json --record @record.json

# chain of a running self-managed connector (its type, sink or source, too)
playground connector smt test --connector my-sink

# a real record, converted like the task would
playground connector smt test --connector my-sink --from-topic orders --partition 0 --offset 42
```

The `--record` format:

```json
{
  "topic": "orders",
  "key": "k1",
  "value": { "schema": { "type": "struct", "fields": [ { "field": "id", "type": "int32" } ] }, "payload": { "id": 1 } },
  "headers": { "source": "web", "version": 2 },
  "timestamp": 1792750000000
}
```

Gotchas:

- **No `--record` and no `--from-topic`**: a schemaless record `{"id": 1, "name": "foo"}` with key `k1`, on the first
  topic of `topics` (or `test-topic`). Handy to check that the chain loads, useless for schema-dependent SMTs
  (`ReplaceField`, `Cast`, `TimestampConverter` on a `Struct`).
- **Schemaless vs `Struct` matters**: most SMTs behave differently (or fail) on a schemaless map and on a `Struct`. If
  the customer uses Avro / Protobuf / JSON Schema, test with `--from-topic` or with the `{"schema", "payload"}`
  envelope, not with plain JSON.
- Headers in `--record` are typed like the `SimpleHeaderConverter` does (string, int64, float64, boolean, map, array).
  Give them as a list `[{"key": …, "value": …}]` for several headers with the same key.
- `--from-topic` reads with the worker's `bootstrap.servers` and security settings, waits up to 15 s for the record,
  and fails with `no record at offset N of partition P of topic T` otherwise.
- A config without `transforms` is accepted with a warning: the record goes through unchanged.
- **Fully managed connectors** are refused with `--connector`: their transforms run in Confluent Cloud. Give their
  config with `--config @file`: the result on a self-managed worker is indicative.

---

## 3. Reading the output

```text
🧪 2 transform(s) on a sink record, Kafka 8.3.2-ce (worker confluentinc/cp-server-connect:8.3.2)
step 0  input
        topic     filestream  partition 0  offset 0  timestamp 2026-10-23T11:10:59.575Z
        key       "k1"   (schemaless)
        value     {"name":"foo","id":1}
        schema    schemaless
step 1  InsertField$Value "AddGroup"  (static.field=group_name, static.value=my group)
        from      Kafka 8.3.2-ce (worker)
        value     {"name":"foo","group_name":"my group","id":1}
step 2  RegexRouter "Route"  (regex=(.*), replacement=$1-copy)
        from      Kafka 8.3.2-ce (worker)
        topic     filestream → filestream-copy
✅ result: topic filestream-copy, key "k1"
        value     {"name":"foo","group_name":"my group","id":1}
```

| Line | Meaning |
| --- | --- |
| `from` | where the class was loaded from: `Kafka <version> (worker)` for built-in SMTs, `owner/name version (plugin <dir>)` for a plugin, `<jar> (given for the test)` for `--smt-jar` / `--smt-plugin` |
| `also in ⚠️ …` | the same class exists in other plugins: the worker could load another copy |
| `predicate X (TopicNameMatches) = false, negate=true` | the predicate result, and whether it's inverted |
| `⏭️ skipped (predicate)` | the transform didn't apply to this record |
| `(no change)` | the transform applied and changed nothing: check its config |
| `schema  + group_name STRING, - name` | fields added, changed or removed in the value schema |
| `🗑️ dropped by step N` | the transform returned `null` |
| `❌ the chain stopped at step N` | the transform threw: the error chain is shown, the stack trace with `--verbose` |

An HTML report of the same steps (the value after each step with the added, changed and removed fields highlighted,
the schema diff, the predicates, the error with its stack trace) is written to
`/tmp/playground-smt-test/smt-test-<connector|chain>-<date>.html` and opened in the browser in an interactive
terminal (`--no-open` to only write it).

Gotchas:

- **`(no change)` is the most useful line.** A misspelled field, a `ReplaceField` `exclude` of a field that's not
  there: silent in Connect, `(no change)` here.
- **Not every mistake is a no-op**: a `TimestampConverter` on a field that doesn't exist **adds it as `null`**
  (`{"name":"foo","created_at":null,"id":1}`), which a sink may then reject or write as an empty column.
- The output stops at the first error or drop: the steps after it are not run, like in Connect.
- `--json` prints the harness result as JSON on stdout (`label`, `kafka_version`, `connector_type`, `steps[]` with
  `alias`, `type`, `config`, `predicate`, `predicate_result`, `negate`, `skipped`, `dropped`, `error`, `stack_trace`,
  `record`), and no report line.
- **The first run is slow**: the harness is compiled in an `eclipse-temurin:17-jdk` container for the Kafka jars of
  the image and cached in `~/.playground-smt-tester`. Later runs take a few seconds.

---

## 4. Versions and plugins: `--cp-version`, `--smt-plugin`, `--smt-jar`

```bash
# the same chain and record with the built-in transforms of two CP versions
playground connector smt test --config @connector.json --record @record.json --cp-version 7.9.0 --cp-version 8.3.2

# an SMT from Confluent Hub, for the test only (the worker is not changed)
playground connector smt test --connector my-sink --smt-plugin confluentinc/connect-transforms:1.6.2

# your own SMT and the jars it depends on, loaded together as one plugin
playground connector smt test --record @record.json --smt-jar target/my-smt.jar --smt-jar lib/dep.jar < connector.json
```

With several `--cp-version`, the run ends with a comparison:

```text
⚖️ final result per CP version
   CP 7.9.0 (Kafka 7.9.0-ce): topic filestream-copy, key null, value {"group_name":"my group","id":1}
   CP 8.3.2 (Kafka 8.3.2-ce): topic filestream-copy, key null, value {"group_name":"my group","id":1}
✅ same result with all the CP versions
```

Gotchas:

- **`--cp-version` runs in throwaway `confluentinc/cp-server-connect:<version>` containers**, pulled if needed (a
  large image per version). Only the **built-in** transforms are there, plus `--smt-plugin` / `--smt-jar`: the plugins
  of the running worker are not. A chain using a connector-bundled SMT fails there with a class-not-found error.
- When an example is running, the throwaway containers join its Docker network and reuse the worker settings, so
  `--from-topic` and Schema Registry converters work with `--cp-version` too. Without a running `connect`,
  `--cp-version` is the only way to run the command.
- The comparison ignores the key order of schemaless maps (it changed between Kafka versions without changing the
  record): `⚠️ the CP versions give different results` means a real difference.
- Test plugins (`--smt-plugin`, `--smt-jar`) are given priority over the worker's plugins: that's how you test a newer
  version of an SMT the worker already has.
- `--smt-plugin` installs with `confluent-hub install` into `~/.playground-smt-tester/plugins/` (cached). The install
  log is next to it when it fails.

---

## 5. Hands-on lab (≈10 min)

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh     # topic "filestream" with 5 JSON records
```

The example's connector has no transforms. Write a chain to a file:

```bash
cat > /tmp/smt-chain.json << 'EOF'
{
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "AddGroup,Route",
  "transforms.AddGroup.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.AddGroup.static.field": "group_name",
  "transforms.AddGroup.static.value": "my group",
  "transforms.Route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.Route.regex": "(.*)",
  "transforms.Route.replacement": "$1-copy"
}
EOF
```

**Step 1: a chain on stdin, on a record of your own**

```bash
playground connector smt test --no-open --record '{"topic":"filestream","key":"k1","value":{"id":1,"name":"foo"}}' < /tmp/smt-chain.json
# step 1  InsertField$Value "AddGroup" … value {"name":"foo","group_name":"my group","id":1}
# step 2  RegexRouter "Route" … topic filestream → filestream-copy
# ✅ result: topic filestream-copy, key "k1"
# 📊 report: /tmp/playground-smt-test/smt-test-chain-<date>.html
```

**Step 2: a real record of the topic, through the converters**

```bash
playground connector smt test --no-open --config @/tmp/smt-chain.json --from-topic filestream --offset 0
# step 0  input  topic filestream  partition 0  offset 0  timestamp <the record's>
#         key null (STRING?)   value {"website":…,"name":"Bonnie.Lehner",…,"id":1,…}   schema schemaless
```

**Step 3: the chain of a running connector**

```bash
playground connector create-or-update -c filestream-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "AddGroup,Filter",
  "transforms.AddGroup.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.AddGroup.static.field": "group_name",
  "transforms.AddGroup.static.value": "my group",
  "transforms.Filter.type": "org.apache.kafka.connect.transforms.Filter",
  "transforms.Filter.predicate": "IsFilestream",
  "transforms.Filter.negate": "true",
  "predicates": "IsFilestream",
  "predicates.IsFilestream.type": "org.apache.kafka.connect.transforms.predicates.TopicNameMatches",
  "predicates.IsFilestream.pattern": "filestream"
}
EOF
playground connector smt test --no-open --connector filestream-sink --from-topic filestream --offset 1
# step 2  Filter "Filter"
#         predicate IsFilestream (TopicNameMatches) = true, negate=true
#         ⏭️ skipped (predicate)
playground connector smt test --no-open --connector filestream-sink --record '{"topic":"other","value":{"id":1}}'
#         predicate IsFilestream (TopicNameMatches) = false, negate=true
#         🗑️ the record is dropped (the transform returned null)
# 🗑️ dropped by step 2           <- exit 0: dropping is a valid result
```

**Step 4: a field added as null, then a failing step**

```bash
playground connector smt test --no-open --record '{"topic":"t","value":{"id":1,"name":"foo"}}' << 'EOF'
{
  "transforms": "Ts,Cast",
  "transforms.Ts.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
  "transforms.Ts.field": "created_at",
  "transforms.Ts.target.type": "Timestamp",
  "transforms.Cast.type": "org.apache.kafka.connect.transforms.Cast$Value",
  "transforms.Cast.spec": "name:int32"
}
EOF
# step 1  TimestampConverter$Value "Ts"  (field=created_at, target.type=Timestamp)
#         value     {"name":"foo","created_at":null,"id":1}     <- the missing field is added, as null
# step 2  Cast$Value "Cast"  (spec=name:int32)
#         ❌ org.apache.kafka.connect.errors.DataException: Value (foo) was out of range for requested data type | Caused by: java.lang.NumberFormatException: For input string: "foo"
# ❌ the chain stopped at step 2 (--verbose or --json for the stack trace)
echo $?   # 1

# a real silent no-op: a typo in the field to drop
playground connector smt test --no-open --record '{"topic":"t","value":{"id":1,"name":"foo"}}' \
  --config '{"transforms":"Drop","transforms.Drop.type":"org.apache.kafka.connect.transforms.ReplaceField$Value","transforms.Drop.exclude":"nme"}'
# step 1  ReplaceField$Value "Drop"  (exclude=nme)
#         (no change)
```

**Step 5: two CP versions, and JSON**

```bash
playground connector smt test --no-open --config @/tmp/smt-chain.json --record '{"topic":"filestream","value":{"id":1}}' \
  --cp-version 7.9.0 --cp-version 8.3.2
# 🔢 CP 7.9.0: throwaway confluentinc/cp-server-connect:7.9.0 … 🔢 CP 8.3.2: throwaway confluentinc/cp-server-connect:8.3.2 …
# ⚖️ final result per CP version
#    CP 7.9.0 (Kafka 7.9.0-ce): topic filestream-copy, key null, value {"group_name":"my group","id":1}
#    CP 8.3.2 (Kafka 8.3.2-ce): topic filestream-copy, key null, value {"group_name":"my group","id":1}
# ✅ same result with all the CP versions
playground connector smt test --config @/tmp/smt-chain.json --record '{"topic":"filestream","value":{"id":1}}' --json \
  | jq -c '.steps[] | {index, alias, topic: .record.topic}'
# {"index":0,"alias":"input","topic":"filestream"}
# {"index":1,"alias":"AddGroup","topic":"filestream"}
# {"index":2,"alias":"Route","topic":"filestream-copy"}
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "records land in the wrong table / topic" | `smt test --config @customer.json --from-topic <t> --offset <o>`: watch the `topic` line of each step (`RegexRouter`, `TimestampRouter`, `ExtractTopic`) |
| "the task fails in an SMT" | the same: the step that throws, its config, its error; `--verbose` for the stack trace to compare with the customer's log |
| "the SMT does nothing" | look for `(no change)` and `⏭️ skipped (predicate)`: a typo in a field name, a predicate that never matches, `negate` the wrong way |
| "records disappear" | `🗑️ dropped by step N`: a `Filter` + predicate, or an SMT returning `null` (tombstone handling) |
| "it broke after the upgrade" | `--cp-version <old> --cp-version <new>`: the comparison says whether the built-in SMTs changed |
| "it works with JSON, not with Avro" | test with the real record (`--from-topic`) or the `{"schema", "payload"}` envelope: `Struct` vs schemaless |
| "we use an SMT from Hub / our own" | `--smt-plugin owner/name:version` or `--smt-jar`, without touching the worker |
| "the same SMT exists in two plugins" | the `also in ⚠️` line: the worker could load another copy (classloader isolation) |
| "fully managed connector" | `--config @file` with its config: indicative only (Confluent Cloud runs its own versions) |

In a repro model, assert on the result instead of reading it:

```bash
result=$(playground connector smt test --connector my-sink --from-topic orders --offset 0 --json)
[ "$(echo "$result" | jq -r '[.steps[] | select(.record)] | last | .record.topic')" == "orders-copy" ] \
  || { logerror "❌ the chain did not route the record to orders-copy"; exit 1; }
```

---

## 7. Cheat sheet

```bash
playground connector smt test [--connector <c> | --config <json|@file> | < config.json] \
  [--record <json|@file> | --from-topic <t> [--partition P] [--offset N]] [--type sink|source] \
  [--cp-version A [--cp-version B]] [--smt-plugin owner/name:version] [--smt-jar <jar>] \
  [--json] [--no-open] [--verbose]
```

- Runs in the `connect` container with the worker's classpath and `plugin.path`: same classes as the connector.
- Step by step like the `TransformationChain`: predicate / `negate`, skip, apply, drop (exit 0), error (exit 1).
- `(no change)` = silent no-op. `also in ⚠️` = the class is in several plugins.
- `--from-topic` = the real bytes through the connector's converters. `--record` = Connect data (schemaless or
  `{"schema", "payload"}`).
- `--cp-version` = throwaway images, built-in SMTs only (+ `--smt-plugin` / `--smt-jar`).
- Report in `/tmp/playground-smt-test/`, harness cached in `~/.playground-smt-tester`.
- Sources: [`connector/smt/test.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/smt/test.sh),
  [`tools/smt-tester/SmtTester.java`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/smt-tester/SmtTester.java),
  [`tools/smt-tester/smt_report.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/smt-tester/smt_report.py),
  helpers `smt_tester_*` in [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🔀 What does this transform chain do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record)
- 👉 Example: [`connect/connect-testing-smt-filestream-sink`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-testing-smt-filestream-sink)
- 🍪 Deep dives: [`connector create-or-update`](/deep-dive-connector-create-or-update.md) to deploy the chain once it
  works, [`topic produce`](/deep-dive-topic-produce.md) for the record to test it on,
  [`connector diagnose` and the dead letter queue](/deep-dive-connector-troubleshooting.md) for records an SMT sends to
  the DLQ (stage `TRANSFORMATION`)
- 🧠 CLI reference: [playground connector smt test](/playground%20connector%20smt%20test)
