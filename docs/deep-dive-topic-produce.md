# 🍪 Deep dive: `playground topic produce`

The command that writes test data for you: give it a schema and it registers the schema and sends realistic random
records that match it. Give it an exact payload and it sends that. The same command works on every environment
(plaintext, SASL, mTLS, Kerberos, RBAC, CFK, Confluent Cloud). Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [📨 Produce realistic test data](/sessions?id=📨-produce-realistic-test-data)
> first. This page goes further: how the command works under the hood, its gotchas, a hands-on lab and recipes for
> support repros.

| You give | What is sent | Serializer | Schema registered |
| --- | --- | --- | --- |
| an **Avro** schema (`"type": "record"`) | random records, generated with `avro-tools random` | `kafka-avro-console-producer` | yes, `<topic>-value` |
| a **JSON Schema** (`"type": "object"`) | random records, generated with `json-schema-faker` | `kafka-json-schema-console-producer` | yes |
| a **Protobuf** schema (`proto3`) | random records, generated with `protobuf-faker` | `kafka-protobuf-console-producer` | yes |
| a **datagen** schema (Avro with `arg.properties`) | JSON strings, generated with `avro-random-generator` (same generator as the Datagen source connector) | `kafka-console-producer` | **no** |
| a **Materialize datagen** JSON (`"_meta"`) or SQL (`CREATE TABLE`) | JSON strings, faker values | `kafka-console-producer` | no |
| anything else (`'{"id": %g}'`, a text) | the payload itself (**raw**) | `kafka-console-producer` | no |

---

## 1. Mental model (the 3 things to remember)

1. **It generates a pool of distinct records, then repeats it.** `--nb-messages 1000000` doesn't mean a million
   different records. The generator runs once, in a Docker image, for at most `--max-nb-messages-to-generate`
   records, and that pool is sent again and again until `--nb-messages` is reached. The output says so:
   `10 records were generated (3 different records, repeated)`. Default pool size:

   | Format | Default pool |
   | --- | --- |
   | Avro, JSON Schema, datagen | 100000 |
   | Protobuf (the generator is slow) | 50 |
   | Materialize datagen JSON / SQL | 1000 |
   | with `--record-size` | 100 |
   | with `--nb-messages -1` | 1000 at most |

   `%g` (and the number in a raw key like `order-007`) are replaced **when the records are sent**, so they keep counting
   across the repeats: `{"id": %g}` sends `{"id": 1}` … `{"id": 1000000}` even with a pool of one record.

2. **The format decides the serializer, and the format is detected from keywords.** In this order: `proto3` →
   Protobuf, `"type": "object"` → JSON Schema, `"_meta"` → JSON, `CREATE TABLE` → SQL, `arg.properties` → datagen,
   `"type": "record"` → Avro, otherwise raw. Avro, JSON Schema and Protobuf go through the Schema Registry
   serializers (magic byte + schema id, schema auto-registered under `<topic>-value` with the default
   `TopicNameStrategy`). Everything else is sent as plain bytes by `kafka-console-producer`, **datagen included**:
   a datagen schema gives JSON records, not Avro ones. Two consequences:
   - a raw payload that happens to contain `"type": "record"` is taken for an Avro schema and fails. Use
     `--value-format raw` (or `--key-format`) to skip detection.
   - key and value must agree: a Schema Registry key needs a Schema Registry value of the **same** format.

3. **It runs next to Kafka, with the environment's credentials.** The console producer runs inside the `connect`
   container (`docker exec`), in `connect-0` with `kubectl exec` on CFK, or in a throw-away container of the connect
   image with the `.ccloud` configuration on Confluent Cloud. The bootstrap server, Schema Registry URL and security
   properties (SASL, mTLS, Kerberos `kinit`, RBAC basic auth) are added for you, which is why the same command line
   works on every environment. The topic is created if it doesn't exist. `--verbose` prints the exact
   `docker exec … kafka-*-console-producer …` command it runs.

---

## 2. What to send: schema, payload, file

```bash
# a schema on stdin: random records that match it (quoted heredoc, so that %g and $ survive the shell)
playground topic produce -t customers --nb-messages 10 << 'EOF'
{
  "type": "record", "name": "Customer", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "name", "type": "string"} ]
}
EOF

# a schema file, or a predefined one (<tab> completion lists them, from scripts/cli/predefined-schemas/)
playground topic produce -t leads --nb-messages 10 --value scripts/cli/predefined-schemas/avro/lead.avsc
playground topic produce -t leads --nb-messages 10 --value @predefined-schemas/protobuf/customer.proto

# an exact payload, %g being the record number
playground topic produce -t ticks --nb-messages 5 --value '{"tick": %g}'

# an exact record, serialized with a schema: --forced-value + the schema
playground topic produce -t customers --forced-value '{"id": 42, "name": "x"}' < customer.avsc

# no schema at hand: derive one from a JSON record (AVRO, JSON or PROTOBUF)
echo '{"order_id": 1, "customer": "acme", "amount": 9.99}' | playground topic produce -t orders --derive-value-schema-as AVRO
```

Gotchas:

- **`--derive-value-schema-as` keeps the shape of your record, not its values.** It derives a schema, then generates
  random records from it (`amount: 0.45`, not `9.99`). To send the record itself, add `--forced-value` with the same
  JSON.
- **`--generate-only`** prints the records without sending anything. Use it to get the skeleton of a record for a
  complex schema, edit one, and send it with `--forced-value`.
- **Raw payloads** from stdin: one JSON per line → one record per line; one multi-line JSON document → minified into a
  single record; any other text → one record per line.
- **Avro unions** are shown in their JSON encoding (`{"string": "Ona"}`): that's the form `--forced-value` expects
  too.
- `--no-null` never generates `null` for optional fields (Avro and JSON Schema only, forced by `--record-size`).

---

## 3. Keys, headers, tombstones

```bash
# raw key with a number: the counter starts there and keeps the zero padding (order-007, order-008, …)
playground topic produce -t orders --nb-messages 3 --key 'order-007' --value '{"id": %g}'

# %g in the key, and headers on every record
playground topic produce -t orders --nb-messages 3 --key 'k%g' --headers 'source:web,version:2' --value '{"id": %g}'

# a key with a schema (same format as the value): random keys too, or an exact one with --forced-key
playground topic produce -t leads --nb-messages 2 --key @predefined-schemas/avro/key.avsc < scripts/cli/predefined-schemas/avro/lead.avsc

# tombstone: null value for that key
playground topic produce -t orders --tombstone --key 'order-007'
```

Gotchas:

- A raw key **without** a number is the same for every record. With a number, it's incremented per record.
- Headers apply to every record. Header keys and values can't contain `,` or `:` (the separators). Records
  themselves can contain `|` or `,`: key, value and headers are joined with an ASCII control character internally.
- `--tombstone` without `--key` sends a record with a null key **and** a null value (with a warning).
- `--headers` and `--tombstone` need CP 7.2+, `--schema-id-in-header` CP 8.1.1+: the command fails early
  otherwise.

---

## 4. Volume, pace and size

```bash
# a lot of records: sent in batches of 300000 (--max-nb-messages-per-batch), with linger.ms=1000 and batch.size=500000
playground topic produce -t load --nb-messages 2000000 --value '{"id": %g}'

# a steady flow until ctrl-c: 20 records/s, progress logged every 10 seconds
playground topic produce -t ticks --nb-messages -1 --throughput 20 --value '{"tick": %g}'

# big records: the first string field is padded to reach the size
playground topic produce -t big --nb-messages 2 --record-size 2000000 < scripts/cli/predefined-schemas/avro/lead.avsc

# partitions, compression, any producer property
playground topic produce -t orders --nb-messages 100 --nb-partitions 3 --key 'k%g' --compression-codec zstd \
  --producer-property acks=all --producer-property client.id=repro --value '{"id": %g}'
```

What happens behind the flags:

| Flag | What it does |
| --- | --- |
| `--nb-messages -1` | infinite, in batches; ctrl-c stops and prints the exact number of records sent |
| `--throughput N` | at most N records per second (paced on the host, before the producer) |
| `--sleep-time-between-batch N` | pause N seconds between batches (bursty load) |
| `--record-size N` | pads the **first string field** of each record; above 1 MB, also sets `max.request.size`, `buffer.memory`, `request.timeout.ms` (60 s instead of the 1.5 s of the console producer) and the topic's `max.message.bytes` for you |
| `--nb-partitions N` | creates the topic with N partitions. If it exists with another count: **re-created when empty, error when not** |
| `--delete-topic` | deletes the topic and its subjects first: a clean slate on re-runs |
| `--consume` | reads the topic back right after (`topic consume --min-expected-messages <sent>`) |

Gotchas:

- **Each call costs a few seconds** (generator container + producer JVM). In a loop, one call per record is slow:
  produce N records in one call instead.
- `--record-size` with a schema that has no string field can't reach the size (warning
  `could not find string field`).
- Because of the pool, 1 million records with `--record-size` are 100 distinct big records repeated: fine for
  throughput tests, not for deduplication or compaction tests (raise `--max-nb-messages-to-generate`).

---

## 5. Schema Registry knobs

| Flag | Use it to reproduce |
| --- | --- |
| `--value-subject-name-strategy TopicRecordNameStrategy` (`RecordNameStrategy`) | several event types in one topic: registers `<topic>-<record full name>` |
| `--compatibility BACKWARD\|FORWARD\|FULL\|NONE…` | sets the compatibility of the subject before producing: an incompatible schema then fails to register |
| `--schema-id-in-header` | the schema id in a record header instead of the payload prefix (`HeaderSchemaIdSerializer`, CP 8.1.1+) |
| `--validate` (+ `--validate-config enhanced.avro.schema.support=true` …) | runs one record through the Connect converter (built for the running CP version, inside the `connect` container) with these converter settings, before sending: catches schemas a sink converter will reject |

- The schema is auto-registered: the same schema on two topics gets the **same id** in two subjects.
- Avro records are produced with `avro.use.logical.type.converters=true` (dates, decimals as logical types).
- `--validate` needs a local `connect` container (not CFK, not Confluent Cloud) and builds a small jar with Maven the
  first time: slow once, then cached.

---

## 6. Hands-on lab (≈10 min)

```bash
playground start-environment --environment plaintext
```

**Step 1: the pool**

```bash
playground topic produce -t lab-pool --nb-messages 10 --max-nb-messages-to-generate 3 < scripts/cli/predefined-schemas/avro/lead.avsc
# ✨ 10 records were generated (3 different records, repeated)    <- records 1, 4, 7, 10 are the same
```

**Step 2: keys and headers**

```bash
playground topic produce -t lab-keys --nb-messages 3 --key 'order-007' --headers 'source:web,version:2' --value '{"id": %g}'
playground topic consume -t lab-keys --min-expected-messages 3 --timeout 30
# Headers:source:web,version:2|Key:order-007|Value:{"id": 1}
# Headers:source:web,version:2|Key:order-008|Value:{"id": 2}
# Headers:source:web,version:2|Key:order-009|Value:{"id": 3}
```

**Step 3: datagen is JSON, not Avro**

```bash
playground topic produce -t lab-trades --nb-messages 2 < scripts/cli/predefined-schemas/datagen/stock_trades_schema.avro
# {"side":"BUY","quantity":3085,"symbol":"ZVV","price":982,"account":"ABC123","userid":"User_6"}
playground schema get --subject lab-trades-value
# ❌ No schema found !                                          <- plain JSON strings
```

**Step 4: derived schema, random values vs your values**

```bash
echo '{"order_id": 1, "customer": "acme", "amount": 9.99}' | playground topic produce -t lab-derived --nb-messages 2 --derive-value-schema-as AVRO
# {"amount":0.45091880238825,"customer":"Furman","order_id":1}  <- the shape, not the values
echo '{"order_id": 1, "customer": "acme", "amount": 9.99}' | playground topic produce -t lab-exact --derive-value-schema-as AVRO \
  --forced-value '{"order_id": 1, "customer": "acme", "amount": 9.99}' --consume
# Value:{"amount":9.99,"customer":"acme","order_id":1}|ValueSchemaId:2
```

**Step 5: detection trap, then `--value-format`**

```bash
playground topic produce -t lab-raw --value '{"type": "record", "note": "not a schema"}'
# 🔮 value schema was identified as avro
# org.apache.avro.SchemaParseException: No name in schema
playground topic produce -t lab-raw --value '{"type": "record", "note": "not a schema"}' --value-format raw
```

**Step 6: tombstone, then the partition guard**

```bash
playground topic produce -t lab-keys --tombstone --key 'order-007'
# order-007|NULL   🧟 Sending tombstone(s)
playground topic produce -t lab-keys --nb-partitions 3 --value x
# --nb-partitions is set, but topic is not empty, delete it first and retry
```

**Step 7: a steady flow**

```bash
playground topic produce -t lab-ticks --nb-messages -1 --throughput 5 --value '{"tick": %g}'
# 🐢 --throughput is set, sending at most 5 records per second
# 💯 51 records sent so far...                                   <- every 10 s; ctrl-c to stop
playground topic get-number-records --topic lab-ticks
```

```bash
playground stop
```

---

## 7. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "sink fails with `Unknown magic byte!`" | send raw JSON to a topic the sink reads with `AvroConverter`: `--value '{"id": %g}'` (no schema, no magic byte) |
| "this one record breaks the connector" | `--generate-only` with the customer's schema for the skeleton, edit, then `--forced-value '<record>'` + the schema |
| "the customer only gave a sample JSON" | `--derive-value-schema-as AVRO --forced-value '<sample>'` (the schema of the sample, the sample itself) |
| "deletes are not applied / tombstones crash the sink" | `--tombstone --key '<id>'` after a few records with the same key |
| "several event types in one topic" | one call per schema with `--value-subject-name-strategy TopicRecordNameStrategy` |
| "the sink converter rejects the schema" | `--validate --validate-config <converter setting>` with the customer's schema |
| "`RecordTooLargeException` / big documents" | `--record-size 2000000` (producer and topic limits are raised for you, the consumer or sink limits are not) |
| "SMT / routing based on headers" | `--headers 'type:invoice,region:eu'` |
| "ordering per key, several partitions" | `--nb-partitions 3 --key 'k%g'` (or a fixed key to pin one partition) |
| "lag, rebalances under steady load" | `--nb-messages -1 --throughput 50` in the background, then `playground connector show-lag` |
| "schema id in headers (new serializers)" | `--schema-id-in-header` (CP 8.1.1+) |

In a repro model, produce **before** creating a sink when the bug is on existing data, and use a quoted heredoc for the
schema:

```bash
playground topic produce -t orders --nb-messages 10 --key 'order-%g' << 'EOF'
{ "type": "record", "name": "Order", "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"} ] }
EOF
playground connector create-or-update --connector jdbc-sink << EOF
{ … }
EOF
```

---

## 8. Cheat sheet

```bash
playground topic produce -t <topic> [--nb-messages N|-1] \
  [< schema | --value '<payload>'|<file>|@predefined-schemas/<fmt>/<file>] [--forced-value '<record>'] \
  [--key '<key>'|<schema> [--forced-key '<key>']] [--headers 'k1:v1,k2:v2'] [--tombstone] \
  [--value-format raw|avro|…] [--derive-value-schema-as AVRO|JSON|PROTOBUF] [--generate-only] \
  [--throughput N] [--record-size BYTES] [--nb-partitions N] [--compression-codec zstd] \
  [--producer-property k=v] [--value-subject-name-strategy …] [--compatibility …] [--validate] \
  [--delete-topic] [--consume] [--verbose]
```

- A pool of distinct records is generated, then repeated. `%g` keeps counting.
- Avro / JSON Schema / Protobuf → Schema Registry serializer. Datagen, JSON, SQL, raw → plain bytes.
- Detection is by keywords: `--value-format raw` when a payload looks like a schema.
- `--derive-value-schema-as` = the shape. Add `--forced-value` for the values.
- Runs in the connect container with the environment's credentials: same command everywhere.
- Source: [`topic/produce.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/topic/produce.sh),
  predefined schemas in [`scripts/cli/predefined-schemas/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/predefined-schemas).

---

**Links**

- 🎬 Video session: [📨 Produce realistic test data](/sessions?id=📨-produce-realistic-test-data)
- 🍪 Deep dive: [`topic consume`](/deep-dive-topic-consume.md), to read back and assert what you produced
- 📖 [Producing data](/reusables?id=👉-producing-data) in the Reproduction toolkit
- 🧠 CLI reference: [playground topic produce](/playground%20topic%20produce) (an example for each flag),
  [playground topic consume](/playground%20topic%20consume), [playground schema](/playground%20schema)
