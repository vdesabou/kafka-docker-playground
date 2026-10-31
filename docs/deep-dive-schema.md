# 🍪 Deep dive: Schema Registry (`playground schema`)

The commands that talk to the Schema Registry of the running environment, local container or Confluent Cloud, without
building the urls and the credentials yourself: list the versions of a subject, register a schema without producing
anything, relax or tighten the compatibility rule, delete a version softly or for good, and derive a schema from a
JSON record. This is how you reproduce "the consumer can't find the schema", "the producer is refused a new version"
or "the sink reads the wrong subject". Takes about 15 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🔰 Schema not found after a cleanup](/sessions?id=🔰-schema-not-found-after-a-cleanup) shows it in 3 minutes: a version refused by `BACKWARD`, the fix with a default, then soft vs permanent delete and what happens to the schema ids.
>
> The [`topic produce` deep dive](/deep-dive-topic-produce.md) shows how schemas get registered when you produce
> (format detection, subject name strategies, `--derive-value-schema-as`), and the
> [`topic consume` deep dive](/deep-dive-topic-consume.md) how the deserializer is chosen from the subjects. This page
> covers the registry itself: subjects, versions, ids, compatibility and deletion, a hands-on lab and recipes for
> support repros.

| You want | Command |
| --- | --- |
| every subject at a glance: versions, latest id, type, rule, mode | `playground schema list [--prefix <p>] [--deleted] [--json]` |
| every version of a subject (or of all subjects) | `playground schema get [--subject <s>]` |
| one version as a plain schema file | `playground schema get --subject <s> --version N --schema-only > vN.avsc` |
| the schema behind an id seen in a record | `playground schema get --id <id>` |
| soft-deleted subjects too | `playground schema get --deleted` |
| a new version, without producing | `playground schema register --subject <s> << 'EOF' … EOF` |
| the rule that accepts or refuses a new version | `playground schema get-compatibility --subject <s>` (or `--global`) / `set-compatibility --compatibility …` |
| the same, on the value subject of a topic | `playground topic set-schema-compatibility --topic <t> --compatibility …` |
| remove a version or a subject | `playground schema delete --subject <s> [--version N] [--permanent] [--dry-run]` |
| a schema from a sample JSON record | `playground schema derive-schema --schema-type AVRO\|JSON\|PROTOBUF << 'EOF' … EOF` |
| freeze or migrate a subject (or the registry) | `playground schema set-mode --subject <s> \| --global --mode READONLY\|IMPORT\|READWRITE` |
| registry-wide behaviour | `playground schema set-normalize --value true` / `validate-new-schemas --value false` |
| one subject name pointing at another | `playground schema set-alias --subject <s> --alias <a>` (CP 7.4.1+) |

---

## 1. Mental model (the 3 things to remember)

1. **Subject, version and id are three different things.** A **subject** is a name (`<topic>-key` / `<topic>-value`
   with the default `TopicNameStrategy`) holding an ordered list of **versions** (1, 2, 3…). Each version points to a
   schema **id**, which is global to the registry: the same schema registered under two subjects gets the **same id**,
   and registering a schema already in a subject returns its existing id and version without creating a new one.
   The id is what travels in every record (the magic byte + 4 bytes, or a header with `--schema-id-in-header`): a
   consumer only needs `GET /schemas/ids/<id>`, never the subject. So:
   - `schema get --subject` answers "which versions does this subject have?",
   - `schema get --id` answers "what is the schema of this record?" (`ValueSchemaId:` in `topic consume`).

2. **Delete is soft by default, and soft keeps the id readable.** A plain `schema delete` marks the versions as
   deleted: the subject disappears from `schema get` (use `--deleted`), its version numbers stay taken, but its ids
   still resolve (`get --id` works), so **existing records still deserialize** in a consumer, which only needs the id.
   (`playground topic consume` is the exception: it picks its deserializer from the subjects, finds none, and shows the
   raw bytes.) `--permanent` (the CLI soft-deletes first,
   as the registry requires) removes the versions for good: once no subject refers to an id any more, `get --id`
   fails with `40403 Schema 2 not found`, which is what a consumer gets on old records. That's the difference between a
   harmless cleanup and the outage the customer is describing.

3. **Compatibility is checked against the subject's rule, only when a new version is registered.** The rule is
   per subject when one was set (`set-compatibility`), otherwise the registry's global one (`BACKWARD` by default).
   It decides whether `register` (or a producer with `auto.register.schemas=true`) is accepted; it never affects
   reading. `get-compatibility --subject` shows the rule in force and where it comes from: the subject-level rule, or
   `🌍 … the global rule of the registry applies` when the subject has none (`--global` reads the global one).

---

## 2. Reading: `list`, `get`, `get --id`, `get --deleted`

```bash
playground schema list                              # one line per subject: versions, latest id, type, rule, mode
playground schema get                               # every version of every subject
playground schema get --subject orders-value        # one subject
playground schema get --id 3                        # the schema behind an id
playground schema get --deleted                     # soft-deleted subjects too, flagged 🧟
playground schema get --subject orders-value --verbose   # also prints the curl commands
playground schema get --subject orders-value --version 2 --schema-only > v2.avsc   # the schema alone (latest without --version)
playground schema get --subject orders-value --json | jq '.[].id'                   # machine-readable, nothing else on stdout
playground schema get --id 3 --json | jq .subjects  # which subjects and versions use this id
```

`schema list` prints one line per subject. A 🌍 marks a compatibility rule or mode inherited from the global setting
of the registry:

```text
SUBJECT       VERSIONS  LATEST  ID  TYPE  COMPATIBILITY  MODE
order-ref     1         v1      4   AVRO  BACKWARD 🌍    READWRITE 🌍
orders-value  2         v2      3   AVRO  FULL           READWRITE 🌍
```

What it prints, per version:

```text
🔰 subject orders-value 💯 version 1 (id 1)
{
  "type": "record",
  "name": "Order",
  …
}
```

Gotchas:

- **A subject with no live version is "not found"**: after a soft delete, `schema get --subject <s>` ends with
  `❌ No schema found !` (exit 1). Add `--deleted` to see it: `🧟 (deleted) subject orders-value 💯 version 1 (id 1)`.
- `--id` prints the raw REST answer (`{"schema": "…", …}`, the schema as an escaped string), not a pretty schema:
  add `--schema-only` for the schema itself, `--json` to also get the subjects and versions that use the id.
  `--id` can't be combined with `--subject`, `--version` or `--deleted`.
- The log lines go to stdout: `get | jq` doesn't parse. Use `--json` (nothing else is printed) or `--schema-only`.
- Protobuf schemas are printed as text, Avro and JSON Schema as pretty JSON.
- Without `--subject`, every subject is read one by one (several REST calls per version): slow on a registry with
  hundreds of subjects. Use `--subject` in scripts.

---

## 3. Writing: `register`, references, `--id`

```bash
# a schema on stdin (quoted heredoc): the format is detected (proto3 → PROTOBUF, "type": "object" → JSON, "type": "record" → AVRO)
playground schema register --subject orders-value << 'EOF'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"} ] }
EOF

# a bundled schema (tab completion), or a file
playground schema register --subject customers-value --schema @scripts/cli/predefined-schemas/avro/customer.avsc

# with references: send the whole request, "schema" + "schemaType" + "references"
playground schema register --subject orders-all-value << 'EOF'
{ "schema": "[\"com.example.Customer\",\"com.example.Product\"]", "schemaType": "AVRO",
  "references": [ {"name": "com.example.Customer", "subject": "customer", "version": 1},
                  {"name": "com.example.Product",  "subject": "product",  "version": 1} ] }
EOF

# data contracts: metadata properties
playground schema register --subject orders-value --metadata-property owner=team-a --metadata-property pii=false < order.avsc
```

What `register` prints is the registry's answer:

```json
{
  "id": 1,
  "version": 1,
  "guid": "0a71363c-ba4f-d94d-aec9-be7c5e130001",
  "schemaType": "AVRO",
  "schema": "{\"type\":\"record\",\"name\":\"Order\",…}"
}
```

Gotchas:

- **A refused schema fails the command**: the registry's error JSON is printed (`"error_code": 40901, "message":
  "Schema being registered is incompatible with an earlier schema for subject …"`), then
  `❌ schema registry refused the schema for subject orders-value (error code 40901)`, exit 1. The log lines go to
  stdout too, so `register | jq` doesn't parse: rely on the exit code.
- **A schema with a `"references"` key is sent as is**: it must already be the full request body (`schema` as an
  escaped string, `schemaType`, `references`). The referenced subjects and versions must exist first. Other schemas
  are wrapped for you.
- A schema that isn't recognized (no `proto3`, no `"type": "object"`, no `"type": "record"`) is refused before any
  call: `❌ no known schema could be identified`. A primitive Avro schema (`"string"`) can't be registered this way.
- **`--id` is a reproduction tool, not a feature**: it backs up the subject, deletes it permanently, switches it to
  `IMPORT` mode, registers the schema at that id (overwriting whatever was there), puts the mode back to
  `READWRITE`, then re-registers the backed-up versions. Use it to reproduce an id collision between two registries.
- `--normalize` asks the registry to normalize this one schema; `set-normalize --value true` does it for every
  registration. Without it, a schema that only differs by whitespace or field order can become a new version.
- The plaintext environment validates Avro defaults (`SCHEMA_REGISTRY_SCHEMA_PROVIDERS_AVRO_VALIDATE_DEFAULTS: true`):
  a `"default"` of the wrong type is refused at registration.

---

## 4. Compatibility: `get-compatibility`, `set-compatibility`, `topic set-schema-compatibility`

```bash
playground schema get-compatibility --subject orders-value                      # the rule in force, and where it comes from
playground schema get-compatibility --global                                    # the default of the registry
playground schema set-compatibility --subject orders-value --compatibility NONE
playground schema set-compatibility --global --compatibility FULL               # every subject without its own rule
playground topic set-schema-compatibility --topic orders --compatibility FULL   # the -value subject of the topic (--include-key: -key too)
playground topic produce -t orders --compatibility NONE …                        # set before producing
```

| Rule | A new version must… | Typical change it accepts |
| --- | --- | --- |
| `BACKWARD` (registry default) | read data written with the **previous** version | add a field **with a default**, remove a field |
| `FORWARD` | be readable by the previous version | add a field, remove a field **with a default** |
| `FULL` | both | add or remove fields **with defaults** only |
| `NONE` | nothing | anything |
| `*_TRANSITIVE` | the same, against **all** past versions | — |

Gotchas:

- **`get-compatibility` says where the rule comes from.** On a subject where none was set, it prints
  `🌍 subject orders-value has no subject-level rule: the global rule of the registry applies` and the global value
  (`BACKWARD` by default). `--json` gives `{"subject": …, "compatibility": …, "source": "subject"|"global"}`.
  `get-mode` works the same way.
- **The rule is checked at registration only.** Relaxing it to `NONE`, registering, then setting it back leaves the
  incompatible version in place: consumers with the old schema fail, and that's often what the customer did.
- `topic set-schema-compatibility` sets the **value** subject only (`<topic>-value`), add `--include-key` for
  `<topic>-key`. It prints the raw REST answer and exits 1 if the registry refused one of them. Without `--topic` it
  asks for confirmation and applies to every topic.
- A subject name strategy other than `TopicNameStrategy` means other subject names
  (`<topic>-<record name>` with `TopicRecordNameStrategy`): set the rule on those, `topic set-schema-compatibility`
  won't find them.

---

## 5. Deleting: soft, permanent, a version, a subject

```bash
playground schema delete --subject orders-value --version 2                 # soft-delete one version
playground schema delete --subject orders-value                             # soft-delete every version
playground schema delete --subject orders-value --permanent                 # soft, then hard: gone for good
playground schema delete --subject orders-value --permanent --dry-run       # what would go, and which ids would stop resolving
playground topic delete --topic orders                                      # the topic, and both subjects, permanently
```

| After | `schema get --subject` | `schema get --deleted` | `schema get --id` | old records | re-register the same schema |
| --- | --- | --- | --- | --- | --- |
| soft delete | `❌ No schema found !` | listed, 🧟 | works | deserialize (`topic consume` shows raw bytes: no subject) | same id, next version number (id 2, version 3) |
| permanent delete | `❌ No schema found !` | not listed | `40403 Schema 2 not found` (if no other subject uses the id) | can't be deserialized any more | a **new id**, version 1 (id 3) |

Gotchas:

- **`--subject` is required**: there is no "delete everything".
- **A refused delete fails the command** (exit 1): `delete --subject orders-value --version 9` prints
  `❌ subject orders-value has no version 9 (versions: 1,2)`. A version used as a reference by another schema can't be
  deleted (`42206`): the command lists who references it, `🔗 version 1 is referenced by schema id 4: order-ref v1`.
- **`--dry-run` deletes nothing** and tells, per version, whether its id keeps resolving:
  `💀 version 1 (id 2): permanent delete, ❌ id 2 will stop resolving: old records written with it can't be
  deserialized any more` (unless another subject uses the same id).
- `--permanent` on a subject that is already soft-deleted skips the soft delete (`🧟 already soft deleted`).
- `playground topic delete` deletes `<topic>-key` and `<topic>-value` **permanently** (unless
  `--skip-delete-schema`): deleting a topic to "start over" in a repro also wipes its schema history.

---

## 6. Deriving a schema: `derive-schema`

```bash
playground schema derive-schema << 'EOF'
{"order_id": 1, "customer": "acme", "amount": 9.99}
EOF

playground schema derive-schema --schema-type PROTOBUF --payload '{"sport": "Football"}'
playground schema derive-schema --schema-type JSON --payload @sample.json
```

It runs the `derive-schema` goal of the Schema Registry Maven plugin, at the version of the playground's default CP
tag, in a `maven` container.

Gotchas:

- **Several records give one schema that covers them all**: one JSON per line; a field with different types across
  records becomes a union (Avro). A single multi-line JSON document is minified into one record.
- **The schema comes from the values you give**: `9.99` → `double`, `1` → `int` (not `long`), a `null` → a null type.
  Give records that show the real range of values, and review the result: it never guesses optional fields or
  logical types (dates, decimals). A JSON `null` becomes `{"type": "null"}` in a JSON Schema.
- The first run downloads the Maven plugin and its dependencies (cached in `~/.m2`): slow once.
- To register the result and produce with it in one go: `topic produce --derive-value-schema-as AVRO` (see the
  [`topic produce` deep dive](/deep-dive-topic-produce.md)).

---

## 7. Registry-wide and subject settings: mode, normalize, validation, alias

| Command | Scope | What it does |
| --- | --- | --- |
| `set-mode --mode READONLY` | subject | registration refused, reads work |
| `set-mode --mode IMPORT` | subject | register at a chosen id and version (migration between registries); needs `mode.mutability=true` on the registry |
| `set-normalize --value true` | registry | canonical form before storing: fewer accidental new versions |
| `validate-new-schemas --value false` | registry | let a schema that newer validation rejects through (default true since CP 8.2.0, stricter Avro 1.12 namespaces) |
| `set-alias --subject <s> --alias <a>` | subject | a client asking for `<a>` gets `<s>` (CP 7.4.1+) |

These commands work with every environment the playground starts: plain http on plaintext / SASL environments,
client certificates on `sasl-ssl` / `2way-ssl`, basic auth `superUser` on RBAC, and the API key of `.ccloud/` on
Confluent Cloud. They're not available on multi data center environments.

---

## 8. Hands-on lab (≈10 min)

```bash
playground start-environment --environment plaintext
```

**Step 1: register, and register again**

```bash
playground schema register --subject orders-value << 'EOF'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"} ] }
EOF
# 🔮 schema was identified as avro
# ⏺️ Registering schema to subject orders-value
# { "id": 1, "version": 1, … }
# … the same command again:
# { "id": 1, "version": 1, … }                <- no new version
playground schema get --subject orders-value
# 🔰 subject orders-value 💯 version 1 (id 1)
```

**Step 2: compatibility refuses, then accepts**

```bash
playground schema get-compatibility --subject orders-value
# 🌍 subject orders-value has no subject-level rule: the global rule of the registry applies
# BACKWARD
playground schema set-compatibility --subject orders-value --compatibility BACKWARD
# BACKWARD
# a required field without default: not BACKWARD compatible
playground schema register --subject orders-value << 'EOF'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"}, {"name": "currency", "type": "string"} ] }
EOF
# { "error_code": 40901, "message": "Schema being registered is incompatible with an earlier schema for subject \"orders-value\", details: [{errorType:'READER_FIELD_MISSING_DEFAULT_VALUE', …" }
# ❌ schema registry refused the schema for subject orders-value (error code 40901)
echo $?   # 1
# the same field with a default: accepted
playground schema register --subject orders-value << 'EOF'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"}, {"name": "currency", "type": "string", "default": "EUR"} ] }
EOF
# { "id": 2, "version": 2, … }
```

**Step 3: records, then a soft delete**

```bash
playground topic produce -t orders --nb-messages 2 << 'EOF'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"}, {"name": "currency", "type": "string", "default": "EUR"} ] }
EOF
playground topic consume -t orders --min-expected-messages 2
# …|Value:{"id":1,"amount":0.80…,"currency":"Isom"}|ValueSchemaId:2       <- the id of version 2
playground schema delete --subject orders-value
playground schema get --subject orders-value
# 🧟 Soft deleting subject 🔰 orders-value   [1, 2]
# ❌ No schema found !
playground schema get --deleted
# 🧟 (deleted) subject orders-value 💯 version 1 (id 1)
# 🧟 (deleted) subject orders-value 💯 version 2 (id 2)
playground schema get --id 2                     # still resolves: { …, "subject": "orders-value", "version": 2, "deleted": true }
playground topic consume -t orders --min-expected-messages 2 --timeout 30
# 🔮🙅 topic is not using any schema for value
# …|Value:                                       <- raw Avro bytes: topic consume finds no subject (a consumer still decodes them by id)
```

**Step 4: a permanent delete**

```bash
playground schema delete --subject orders-value --permanent --dry-run
# 💀 version 3 (id 2): permanent delete, ❌ id 2 will stop resolving: old records written with it can't be deserialized any more
playground schema delete --subject orders-value --permanent
playground schema get --id 2
# 🔥 ❌ Command failed with error code 40403
# 🔥 Schema 2 not found                          <- what a consumer gets for the 2 records: they're lost for good
playground schema register --subject orders-value << 'EOF'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"} ] }
EOF
# { "id": 3, "version": 1, … }                   <- a new id: the old records stay unreadable
```

**Step 5: derive a schema**

```bash
playground schema derive-schema << 'EOF'
{"order_id": 1, "customer": "acme", "amount": 9.99}
{"order_id": 2, "customer": "globex", "amount": 12}
EOF
# 🪄 Schema file generated
# 🪄 Schema file generated
# { "type": "record", "name": "Schema", "fields": [ {"name": "amount", "type": "double"}, {"name": "customer", "type": "string"}, {"name": "order_id", "type": "int"} ] }
playground schema derive-schema --schema-type PROTOBUF --payload '{"sport": "Football"}'
# syntax = "proto3";
# message Schema {
#   string sport = 1;
# }
```

```bash
playground stop
```

---

## 9. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "`Schema not found` / `Error retrieving Avro schema for id N`" after a cleanup | produce, `schema delete --subject <s> --permanent`, consume: the skipped-records warning shows the failure; a soft delete doesn't reproduce it |
| "the producer gets `Schema being registered is incompatible`" | `set-compatibility` to the customer's rule, `register` v1 then the customer's v2: the 409 is the registry's verdict |
| "consumers broke after someone relaxed compatibility" | `set-compatibility NONE`, `register` the incompatible version, set the rule back, consume old and new records |
| "which schema is this record using?" | `topic consume -t <t> --last 1` for `ValueSchemaId:`, then `schema get --id <id>` |
| "the sink reads the wrong subject / subject not found" | the producer's subject name strategy: `schema get` to list the real subjects, `topic consume --value-subject` to read them (see the [`topic consume` deep dive](/deep-dive-topic-consume.md)) |
| "the same schema keeps creating new versions" | register twice with a whitespace change, then `set-normalize --value true` and again |
| "a schema registered years ago is refused after an upgrade" | `validate-new-schemas --value true` (CP 8.2 default) vs `false` on the same schema |
| "we migrated subjects and the ids changed" | `register --id <id>` on the target registry (IMPORT mode under the hood) |
| "we only have a sample message" | `derive-schema`, review, then `register` or `topic produce --derive-value-schema-as` |

In a repro model, register the customer's schemas **before** creating the connector, and fail fast when the registry
refuses them:

```bash
playground schema register --subject orders-value < customer-v1.avsc      # exits 1 if the registry refuses it
playground schema set-compatibility --subject orders-value --compatibility FULL
```

---

## 10. Cheat sheet

```bash
playground schema list [--prefix <p>] [--deleted] [--json]
playground schema get [--subject <s> [--version N|latest] | --id <id>] [--deleted] [--schema-only | --json] [--verbose]
playground schema register --subject <s> [--schema @file] [--metadata-property k=v]... [--normalize] [--id <id>] << 'EOF' … EOF
playground schema get-compatibility --subject <s> | --global [--json]
playground schema set-compatibility --subject <s> | --global --compatibility BACKWARD|FORWARD|FULL|NONE[_TRANSITIVE]
playground topic set-schema-compatibility --topic <t> --compatibility … [--include-key]
playground schema delete --subject <s> [--version N] [--permanent] [--dry-run]
playground schema derive-schema [--schema-type AVRO|JSON|PROTOBUF] [--payload '<json>'|@file] << 'EOF' … EOF
playground schema get-mode|set-mode --subject <s> | --global [--mode READWRITE|READONLY|IMPORT]
playground schema set-normalize|validate-new-schemas --value true|false
playground schema get-alias|set-alias --subject <s> [--alias <a>]
```

- Subject = name, version = position in the subject, id = global, in every record.
- Soft delete: hidden, ids still resolve. `--permanent`: gone, old records fail.
- Compatibility: per subject (else global `BACKWARD`), checked at registration only.
- `register` and `delete` exit 1 when the registry refuses the request.
- Sources: [`commands/schema/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/schema),
  [`topic/set-schema-compatibility.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/topic/set-schema-compatibility.sh),
  `get_sr_url_and_security` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🔰 Schema not found after a cleanup](/sessions?id=🔰-schema-not-found-after-a-cleanup)
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md) (schemas registered while producing, subject name
  strategies), [`topic consume`](/deep-dive-topic-consume.md) (deserializer chosen from the subjects, skipped records)
- 👉 Examples: [`other/schema-references`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-references),
  [`other/recover-from-schema-hard-deletion`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/recover-from-schema-hard-deletion)
- 📖 Confluent docs: [schema deletion](https://docs.confluent.io/platform/current/schema-registry/schema-deletion-guidelines.html),
  [compatibility types](https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html#compatibility-types)
- 🧠 CLI reference: [playground schema](/playground%20schema), [playground topic set-schema-compatibility](/playground%20topic%20set-schema-compatibility)
