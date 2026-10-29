# 🍪 Deep dive: `playground topic consume`

The command that reads a topic for you: it picks the right deserializer, prints every record on one line with its
partition, offset, timestamp, headers, key and schema ids, and turns into an **assertion** in scripts (at least N
records, a record containing X). The same command works on every environment (plaintext, SASL, mTLS, Kerberos, RBAC,
CFK, Confluent Cloud). Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [📥 Read a topic](/sessions?id=📥-read-a-topic) first. This page goes
> further: how the command works under the hood, its gotchas, a hands-on lab and recipes for support repros.

| You want | Flags |
| --- | --- |
| the first records (default: 100) | `-t <topic>` (`--max-messages N`, `-1` for all) |
| the most recent records | `--last N` |
| the records from a time | `--from-timestamp "2026-10-22 10:30"` / `10m` / `<epoch>` |
| one exact record | `--partition P --offset O --max-messages 1` |
| new records as they arrive | `--tail` |
| to fail when data is missing | `--min-expected-messages N --timeout 60`, `--grep <string>` |
| a number | `--count` (all topics without `-t`) |
| records for `jq` | `--json` |
| everything in an editor | `--open` |

---

## 1. Mental model (the 3 things to remember)

1. **The deserializer comes from Schema Registry subjects, not from the bytes.** Before reading, the command looks up
   the latest version of `<topic>-key` and `<topic>-value`. If the value subject exists, it runs
   `kafka-avro-console-consumer` (or `-protobuf-`, `-json-schema-`, after the subject's `schemaType`), otherwise plain
   `kafka-console-consumer`. Two consequences:
   - data produced with `RecordNameStrategy` / `TopicRecordNameStrategy` has no `<topic>-value` subject: it's printed
     as raw Avro bytes until you pass `--value-subject <subject>` (or `--key-subject`).
   - a topic **with** a value subject where some records are not Schema Registry encoded: those records are skipped
     (`--skip-message-on-error`), counted, and reported once with the root cause, e.g.
     `⚠️ 1 record(s) … could not be deserialized and were skipped … (caused by: java.lang.IllegalArgumentException: Unknown magic byte!)`.

   A schema key is only decoded when the value uses a schema too: otherwise the key is read as a string.

2. **"It contains N messages" counts offsets, the assertion counts records.** The number in the first log line comes
   from `topic get-number-records`: end offset minus start offset, per partition. Transaction markers, compacted
   records and skipped records use offsets but are not records. `--min-expected-messages N`:
   1. waits (polling every second, up to `--timeout`, default 60 s) until the topic holds N offsets. A topic that
      doesn't exist yet is waited for, up to 60 s.
   2. consumes, and stops when no record arrives for 10 seconds (30 s on Confluent Cloud), so it never hangs on
      offsets that hold no record.
   3. fails unless at least N records were **actually consumed and deserialized**.

   `--count` uses the same rule: records, not offsets.

3. **It runs next to Kafka, with the environment's credentials, in its own consumer group.** The console consumer runs
   inside the `connect` container (`docker exec`), in `connect-0` with `kubectl exec` on CFK, or in a throw-away
   container of the connect image on Confluent Cloud, with the bootstrap server, Schema Registry URL and security
   properties added for you. Each call reads from the beginning in a new throw-away group (`console-consumer-<n>`, they
   show up in `playground consumer-group list`): it never moves the offsets of your connectors or applications. `--verbose` prints the exact command, with the passwords masked.

---

## 2. Reading: what and where

```bash
# the first 100 records, partition by partition
playground topic consume -t orders

# all of them, without truncating long values (default: 3000 characters per record)
playground topic consume -t orders --max-messages -1 --max-characters 0

# the 10 most recent, or from a time (local time, Z for UTC, an epoch in s or ms, or 30s / 10m / 2h / 1d ago)
playground topic consume -t orders --last 10
playground topic consume -t orders --from-timestamp "2026-10-22 10:30" --max-messages 20
playground topic consume -t orders --from-timestamp 10m

# the record a connector is stuck on: one partition, one offset
playground topic consume -t orders --partition 2 --offset 1234 --max-messages 1

# follow new records (ctrl-c to stop), optionally on one partition
playground topic consume -t orders --tail

# the registered schemas too, or a full dump opened in your editor (/tmp/dump-<topic>-<date>.log)
playground topic consume -t orders --print-schema
playground topic consume -t orders --open
```

What a record looks like:

```text
CreateTime:2026-10-23 12:31:24.766|Partition:0|Offset:0|Headers:NO_HEADERS|Key:order-2|Value:{"count":2,…}|ValueSchemaId:1
```

`KeySchemaId:` is added after the key when the key uses a schema. A tombstone shows `Value:null`.

Gotchas:

- **The default order is partition by partition, not time.** Partition 0 first, then 1… `--last` and
  `--from-timestamp` run one consumer per partition and sort the records by timestamp across partitions.
- **`--tail` starts at the end**: it only shows records produced after it started.
- `--last`, `--from-timestamp` and `--partition` need CP 7.0+.
- Values that look base64 encoded (the first record is valid base64 of printable UTF-8: bytes written by a
  `JsonConverter` or `ByteArrayConverter`) are decoded for display (`🤖 Data is base64 encoded, payload will be
  decoded`). Use `--no-decode` to see the bytes as stored.
- A long record is cut at `--max-characters` (`...<truncated, only showing first 3000 characters, out of 2001234>...`).
- `--isolation-level read_committed` hides aborted transactional records. The count of the first log line follows
  the same isolation level.

---

## 3. Asserting: in examples and repro models

```bash
# at least 10 records within 120 seconds, or exit 1
playground topic consume -t orders --min-expected-messages 10 --timeout 120

# a record containing this string, or exit 1 (searched in the line as displayed: key, headers, decoded value)
playground topic consume -t orders --grep '"status":"PAID"'

# both: wait for the data, then look for the string
playground topic consume -t dlq --min-expected-messages 1 --timeout 60 --grep 'Unknown magic byte'
```

The failures, as printed:

```text
❌ overall timeout of 5 seconds exceeded. --min-expected-messages is set with 20 but topic ticks contains 10 messages
❌ --min-expected-messages is set with 6 but only 5 records could be consumed from topic orders (6 offsets, 1 could not be deserialized)
❌ could not find nope in topic ticks
```

Gotchas:

- `--timeout` without `--min-expected-messages` is an error: the timeout is the wait for the records.
- `--min-expected-messages` is a minimum: more records is fine. For an exact number, use `--count` and compare.
- `--grep` only prints the matching records, and `--grep … --count` prints how many match.
- A source connector that writes nothing yet: `--min-expected-messages` waits for the topic to be created (60 s),
  then for the records (`--timeout`). That's the replacement for a `sleep` in a script.

---

## 4. Scripting: `--json` and `--count`

```bash
# one json object per line on stdout, logs on stderr: pipe to jq
playground topic consume -t orders --json | jq -c '{partition, offset, key, first: .value.first_name, value_schema_id}'
# {"partition":0,"offset":0,"key":"order-2","first":"Doris","value_schema_id":1}

# a number on stdout
n=$(playground topic consume -t orders --count)

# every topic (internal ones excluded): "<topic> <number>" per line
playground topic consume --count
```

Each `--json` record has `topic`, `partition`, `offset`, `timestamp_type`, `timestamp` (ms), `date`, `headers` (an
object), `key`, `value`, and `key_schema_id` / `value_schema_id` when there is one. Key and value are embedded as JSON
when they are valid JSON, as strings otherwise.

`--count` vs [`topic get-number-records`](/playground%20topic%20get-number-records): the first consumes and counts
records (exact, slower on big topics), the second subtracts offsets (instant, but counts markers and compacted
records).

---

## 5. Hands-on lab (≈10 min)

```bash
playground start-environment --environment plaintext
playground topic produce -t orders --nb-messages 5 --key 'order-%g' --nb-partitions 3 < scripts/cli/predefined-schemas/avro/customer.avsc
playground topic produce -t ticks --nb-messages 10 --value '{"tick": %g}'
```

**Step 1: default order and positioning**

```bash
playground topic consume -t orders
# Partition:0|Offset:0 … order-2, Partition:0|Offset:1 … order-3, Partition:1 … order-1, Partition:2 … order-4, order-5
playground topic consume -t orders --last 2 --max-characters 90
# ⏮️ Display the last 2 records of topic orders          <- sorted by timestamp across partitions
playground topic consume -t orders --partition 2 --offset 1 --max-messages 1
# 🧭 Display records of topic orders, partition 2, from offset 1
```

**Step 2: assertions that fail**

```bash
playground topic consume -t ticks --min-expected-messages 20 --timeout 5
# ❌ overall timeout of 5 seconds exceeded. --min-expected-messages is set with 20 but topic ticks contains 10 messages
playground topic consume -t ticks --grep '"tick": 7' --count
# ✅ found "tick": 7 in 1 record(s) of topic ticks
# 1
```

**Step 3: offsets are not records**

```bash
playground topic produce -t orders --value 'not avro' --value-format raw      # a record without magic byte in an Avro topic
playground topic consume -t orders --min-expected-messages 6
# ⚠️ 1 record(s) of topic orders could not be deserialized and were skipped, first error:
#    org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID (caused by: java.lang.IllegalArgumentException: Unknown magic byte!)
# ❌ --min-expected-messages is set with 6 but only 5 records could be consumed from topic orders (6 offsets, 1 could not be deserialized)
```

**Step 4: a subject that doesn't follow the topic name**

```bash
playground topic produce -t events --nb-messages 1 --value-subject-name-strategy TopicRecordNameStrategy < scripts/cli/predefined-schemas/avro/customer.avsc
playground topic consume -t events
# 🔮🙅 topic is not using any schema for value
# …|Value:<raw Avro bytes: no magic byte decoding, unreadable strings>
playground topic consume -t events --value-subject events-com.github.vdesabou.Customer
# …|Value:{"count":1,"first_name":…}|ValueSchemaId:1
```

**Step 5: base64, tombstone, tail**

```bash
playground topic produce -t b64 --value 'eyJpZCI6IDF9'
playground topic consume -t b64                  # 🤖 Data is base64 encoded … Value:{"id": 1}
playground topic consume -t b64 --no-decode      # Value:eyJpZCI6IDF9
playground topic produce -t ticks --tombstone --key k1
playground topic consume -t ticks --last 1       # Key:k1|Value:null
playground topic consume -t ticks --tail         # in another terminal: playground topic produce -t ticks --value 'live-%g' --nb-messages 2
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "the connector is stuck on offset X" | `--partition <p> --offset <X> --max-messages 1 --print-schema`: the exact record and its schema |
| "what is in the dead letter queue?" | [`playground topic dlq inspect`](/playground%20topic%20dlq%20inspect) groups the errors; `topic consume -t <dlq> --last 5` shows the raw records and their `__connect.errors.*` headers |
| "the sink says `Unknown magic byte!`" | consume the topic: the skipped-records warning gives the offsets count and the root cause, `--no-decode` shows the bytes |
| "garbage values, but the producer uses a schema" | `playground schema get` to list subjects, then `--value-subject <subject>` (name strategies other than `TopicNameStrategy`) |
| "records arrived around 10:30" | `--from-timestamp "2026-10-22 10:25" --max-messages 50` |
| "did the source connector write anything?" | `--min-expected-messages 1 --timeout 120` (waits for the topic, then the records) |
| "transactional producer / read_committed sink sees fewer records" | compare `--count` with `--count --isolation-level read_committed`, and with `topic get-number-records`; an open transaction blocks `read_committed` readers at its start offset: `playground broker transactions describe-producers --topic <t>` |
| "count per key / extract one field" | `--json --max-messages -1 \| jq -r '.key' \| sort \| uniq -c` |
| "share the topic content" | `--open` (full dump, no truncation, in `/tmp/dump-<topic>-<date>.log`) |

In a repro model, replace `sleep` + eyeballing with an assertion, so that `playground run` fails when the scenario
doesn't:

```bash
playground connector create-or-update --connector my-source << EOF
{ … }
EOF
playground topic consume -t my-topic --min-expected-messages 10 --timeout 120 --grep '"id":10'
```

---

## 7. Cheat sheet

```bash
playground topic consume [-t <topic>] \
  [--max-messages N|-1] [--last N] [--from-timestamp <date|epoch|10m>] [--partition P [--offset O|earliest|latest]] [--tail] \
  [--min-expected-messages N [--timeout S]] [--grep <string>] [--count] [--json] \
  [--key-subject <s>] [--value-subject <s>] [--print-schema] [--isolation-level read_committed] \
  [--max-characters N|0] [--no-decode] [--open] [--verbose]
```

- Deserializer = Schema Registry subjects `<topic>-key` / `<topic>-value`. Other names: `--value-subject`.
- "Contains N messages" = offsets. Assertions and `--count` = records actually deserialized.
- Default order: by partition. `--last` / `--from-timestamp`: by timestamp.
- `--tail` = new records only.
- Stops after 10 s without records (30 s on Confluent Cloud). Own throw-away group: never moves your consumer groups.
- Source: [`topic/consume.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/topic/consume.sh).

---

**Links**

- 🎬 Video session: [📥 Read a topic](/sessions?id=📥-read-a-topic)
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md), to write the data you read here;
  [`connector diagnose` and the dead letter queue](/deep-dive-connector-troubleshooting.md), to read a DLQ by error;
  [offsets and lag](/deep-dive-offsets-and-lag.md), to move a connector to the record you found
- 📖 [Consuming data](/reusables?id=👉-consuming-data) in the Reproduction toolkit
- 🧠 CLI reference: [playground topic consume](/playground%20topic%20consume),
  [playground topic get-number-records](/playground%20topic%20get-number-records),
  [playground topic dlq inspect](/playground%20topic%20dlq%20inspect)
