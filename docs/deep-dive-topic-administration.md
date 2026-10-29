# 🍪 Deep dive: topic administration (`playground topic`)

The commands that manage topics themselves, not their records: create a topic with the partitions and configs a
repro needs, change a config on a live topic, see partitions and overrides, count and measure what a topic holds, wait
until a connector has written something, and delete topics (with their Schema Registry subjects). The same commands
work on every environment the playground starts, local or Confluent Cloud. Around them, the `playground broker`
commands check the health of the cluster, stop, start and restart brokers, inspect transactions and broker metrics
(local environments). Takes about 20 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🪛 A producer gets RecordTooLargeException](/sessions?id=🪛-a-producer-gets-recordtoolargeexception) shows it in 3 minutes: a topic created with the customer's configs, a `max.message.bytes` override that reproduces `RecordTooLargeException`, and the fix.
>
> Writing and reading records have their own pages: [`topic produce`](/deep-dive-topic-produce.md),
> [`topic consume`](/deep-dive-topic-consume.md), and [`topic dlq`](/deep-dive-connector-troubleshooting.md) for dead
> letter queues. This page covers the topic around them: partitions, configs, counts, sizes and deletion, a hands-on lab
> and recipes for support repros.

| You want | Command |
| --- | --- |
| a topic with N partitions and some configs | `playground topic create -t <t> --nb-partitions 3 --config retention.ms=60000` |
| change a config of a live topic | `playground topic alter -t <t> --add-config max.message.bytes=1000` (`--delete-config <k>` to remove it) |
| change a config of the live brokers (the default of every topic, threads, throttles) | `playground broker config set --key log.retention.ms --value 60000` (`--broker <id>` for one broker, `get --key <k>` for the value and its source, `delete --key <k>`) |
| is the cluster healthy? (a broker down, under-replicated, under min ISR or offline partitions, KRaft quorum) | `playground broker health` (`--wait-healthy --max-wait 120`, `--json`; exit 1 when not healthy) |
| stop a broker (or crash it), start it again, restart them one by one | `playground broker stop --broker 2` (`--kill`) / `playground broker start --broker 2` / `playground broker rolling-restart` (needs `--enable-multiple-brokers`) |
| open and hanging transactions (a `read_committed` consumer stuck) | `playground broker transactions list\|describe\|describe-producers\|find-hanging\|abort` |
| brokers, active controller, `metadata.version`, API versions | `playground broker describe` (`--api-versions --broker <id>`) |
| is the broker the bottleneck? (idle threads, p99 latency, bytes in/out) | `playground broker metrics` (`--topic <t>`, `--json`) |
| partitions, replicas, ISR and config overrides | `playground topic describe [-t <t>]` |
| the topics (without or with internal ones) | `playground topic list [--show-internal]` |
| the topics by disk size | `playground topic list --sort-by-size` / `playground topic get-size [-t <t>]` |
| how many records (cheap) | `playground topic get-number-records [-t <t>]` |
| earliest / latest offset per partition | `playground topic get-offsets [-t <t>]` |
| wait until a topic has N records (scripts) | `playground topic wait-for-records -t <t> --min-expected-messages N --max-wait 120` |
| delete topics (a regex works) and their subjects | `playground topic delete -t <t>` (`--skip-delete-schema`) |
| what consumer groups committed, raw | `playground topic display-consumer-offsets` (follows: ctrl-c) |
| Stream Catalog tags (Confluent Cloud) | `playground topic tag list\|create\|add\|remove\|show\|search\|delete` |

---

## 1. Mental model (the 3 things to remember)

1. **They are thin wrappers around the Kafka tools, run next to the broker.** `create` is `kafka-topics --create`,
   `alter` is `kafka-configs --alter --entity-type topics`, `describe` is `kafka-topics --describe`, run with
   `docker exec` in the broker (or connect) container with the environment's credentials, in a throw-away container
   with the `.ccloud` configuration on Confluent Cloud, and through `kubectl` on CFK. Every argument the playground
   doesn't know (`--config`, `--replication-factor`, `--add-config`, `--delete-config`…) is passed through as is.
   `--verbose` prints the exact command.

2. **"Number of records" is offsets, not records.** `get-number-records` sums **latest − earliest offset** of every
   partition (`GetOffsetShell --time -1` and `--time -2`): it costs nothing, but transaction markers and compacted
   records still count. `get-offsets` shows earliest and latest per partition and their difference.
   For the records you can actually read, use `topic consume --count`. On Confluent Cloud, `get-number-records` reads
   the topic with kcat instead and counts real records.

3. **The topic list comes from the broker's data folders.** On Docker, `list`, `create`, `alter`, `delete` and
   `get-number-records` decide whether a topic exists by listing `/var/lib/kafka/data` of the brokers, not by asking
   the cluster. It's fast, and it means "internal" is a naming rule: `--skip-internal-topics` (the default of `list`,
   `describe`, `get-number-records` without `-t`) hides every topic whose name starts with `_` **or with `connect-`**.

---

## 2. Creating and changing: `create`, `alter`

```bash
# 3 partitions, two configs (any kafka-topics --create argument is passed through)
playground topic create -t orders --nb-partitions 3 --config retention.ms=600000 --config cleanup.policy=compact

# a config on a live topic, and back to the broker default
playground topic alter -t orders --add-config max.message.bytes=1000
playground topic alter -t orders --delete-config max.message.bytes

# several at once: comma separated, as kafka-configs wants
playground topic alter -t orders --add-config retention.ms=1000,segment.ms=1000
```

Gotchas:

- **`create` fails on an existing topic**: `❌ topic orders already exist !`, exit 1. Delete it first, or use
  `alter` for configs.
- **`alter` on a missing topic creates it first** (`🆕 topic orders does not exist, creating it...`), with 1 partition,
  then applies the configs.
- **The replication factor is the broker's default**: 1 on the single-broker environments. Pass
  `--replication-factor 3` with `--enable-multiple-brokers`: on a single broker, creation fails.
- **The number of partitions can't be changed with `alter`** (`kafka-configs` only touches configs). `topic produce
  --nb-partitions N` re-creates an **empty** topic with N partitions and refuses a non-empty one (see the
  [`topic produce` deep dive](/deep-dive-topic-produce.md)).
- **Retention is not immediate**: `retention.ms=1000` only deletes **closed** segments. Add `segment.ms` (or produce
  enough to roll a segment), then wait for the log cleaner (`log.retention.check.interval.ms`, 5 minutes by default).
  Same for compaction (`cleanup.policy=compact`): the active segment is never compacted.
- A topic is also created on the fly by a producer when `auto.create.topics.enable` is on (the broker default,
  not overridden by the environments): create it yourself when the repro depends on its partitions or configs.

---

## 3. Looking at topics: `describe`, `list`, `get-size`

```bash
playground topic describe -t orders
playground topic describe                          # every non-internal topic
playground topic list                              # internal topics excluded
playground topic list --show-internal              # _schemas, __consumer_offsets, connect-offsets…
playground topic list --sort-by-size               # = get-size: largest first
playground topic get-size -t orders
```

`describe` prints what `kafka-topics --describe` prints:

```text
Topic: lab-orders	TopicId: FZbifE9XRBemai7WDrFzSw	PartitionCount: 3	ReplicationFactor: 1	Configs: min.insync.replicas=1,retention.ms=600000
	Topic: lab-orders	Partition: 0	Leader: 1	Replicas: 1	Isr: 1	Offline: 	Elr: 	LastKnownElr: 
	…
```

`Configs:` lists the **overrides** set on the topic (and a few broker settings, such as `min.insync.replicas`), not
every effective value.

Gotchas:

- **A topic named `connect-…` is hidden like an internal one** by `list`, `describe` without `-t`, and the
  "all topics" mode of `get-number-records`, `get-size` and `topic consume`. Name repro topics something else, or pass
  `-t`.
- **`get-size` measures disk, per replica**: the size of a partition is its largest replica, the size of a topic the
  sum of its partitions. A freshly written topic can show 0 until the segment is flushed. On Confluent Cloud, sizes come
  from the Metrics API (`retained_bytes`, a few minutes late) and need `CONFLUENT_CLOUD_API_KEY` /
  `CONFLUENT_CLOUD_API_SECRET`.
- On CFK, `describe` shows the `KafkaTopic` custom resource (`kubectl describe kafkatopic`) **and** `kafka-topics
  --describe`.

---

## 4. Counting and waiting: `get-number-records`, `get-offsets`, `wait-for-records`

```bash
playground topic get-number-records -t orders      # one number
playground topic get-number-records                # every non-internal topic
playground topic get-offsets -t orders             # earliest, latest and their difference per partition
playground topic wait-for-records -t orders --min-expected-messages 10 --max-wait 120   # scripts
```

`get-offsets` output:

```text
📍 Earliest and latest offsets per partition of topic lab-orders
PARTITION  EARLIEST        LATEST          RECORDS
0          0               2               2
1          0               5               5
2          0               3               3
TOTAL                                      10
```

| Command | Counts | Cost | Wrong when |
| --- | --- | --- | --- |
| `get-number-records` | sum of latest − earliest offsets (Confluent Cloud: records read with kcat) | instant | compaction, transactions (markers use offsets) |
| `get-offsets` | latest − earliest per partition | instant | compaction, transactions (markers use offsets) |
| `topic consume --count` | records actually read and deserialized | reads everything | never: it's the reference |

Gotchas:

- **`wait-for-records` polls `get-number-records`** every `--interval` seconds (5) up to `--max-wait` (120): it
  inherits its counting, so it can return early on offsets that hold no readable record (a transaction marker). A topic
  that doesn't exist yet counts as 0, so you can call it before a source connector created its topic. On timeout:
  `❌ topic orders contains 0 records after 10 seconds, expected at least 1`, exit 1.
- `get-number-records` on a missing topic prints `topic … does not exist !` (a warning) and exits 0: check the number,
  not the exit code.
- `get-offsets` needs CP 7.0+.
- **To assert data in a script, prefer `topic consume --min-expected-messages N`** (counts real records, then shows
  them) to `wait-for-records` + a count.

---

## 5. Deleting: `delete`

```bash
playground topic delete -t orders                         # the topic, and orders-key / orders-value permanently
playground topic delete -t orders --skip-delete-schema    # keep the subjects
playground topic delete -t 'lab-.*'                       # a regex, matched against the whole name
```

Gotchas:

- **The subjects go with the topic, permanently.** `delete` hard-deletes `<topic>-key` and `<topic>-value` when they
  exist: re-creating the topic starts a new schema history, and records still around elsewhere (a mirror, a DLQ) can't
  be decoded any more. That's usually what a repro wants; `--skip-delete-schema` when it isn't. Subjects of other
  naming strategies (`<topic>-<record>`) are not touched. See the [schema deep dive](/deep-dive-schema.md).
- **`--topic` is a regex when no topic has that exact name**, matched in full (`^(…)$`): `lab-.*` deletes every topic
  starting with `lab-`, internal ones included if they match. The matching topics are printed before they're deleted.
- **Nothing matching is not an error**: `❌ topic lab-nope does not exist and regex does not match any topic !`, exit 0.
  When `--topic` is a plain topic name (no regex characters other than `.`), leftover `<topic>-key` / `<topic>-value`
  subjects are still deleted (`🔰 Delete subject <topic>-value (its topic does not exist)`): a subject that outlived its
  topic would otherwise make the next producer with another schema fail with `40901` (incompatible schema).
- Deletion is asynchronous in Kafka: a topic re-created right after can fail with `TopicExistsException` or
  `marked for deletion` for a moment.
- **A subject goes with the topic**: `delete` hard-deletes `<topic>-key` / `<topic>-value` (soft, then hard: the
  output shows both), so the schema ids of its records are gone too (see the [Schema Registry deep dive](/deep-dive-schema.md)).
- On Confluent Cloud, it also forgets the topic in the list of topics the playground created (cleaned by
  `playground stop` / the ccloud cleanup).

---

## 6. Consumer offsets and tags: `display-consumer-offsets`, `tag`

- **`display-consumer-offsets` decodes `__consumer_offsets`** from the beginning and **follows it** (ctrl-c): every
  commit of every group, connectors' `connect-<name>` included, as `[group,topic,partition]::OffsetAndMetadata(…)`.
  Run it with `timeout 15` in a script. Not readable on Confluent Cloud. For a group's current position, `playground
  consumer-group describe --group <g>` is easier (see the [offsets and lag deep dive](/deep-dive-offsets-and-lag.md)).
- **`tag` is Confluent Cloud only** (Stream Catalog): `tag create --tag PII`, `tag add -t orders --tag PII`,
  `tag search --tag PII`. A topic created a moment ago can take a minute to appear in the catalog before it can be
  tagged.

---

## 7. The brokers: `broker health`, `stop` / `start`, `rolling-restart`, `transactions`, `describe`, `metrics`

The `playground broker` commands look at the cluster rather than one topic. Like the topic commands, they run the
Kafka tools next to the broker with the environment's credentials (plaintext, secured environments; `health`,
`transactions` and `describe` on CFK too), and are not available on Confluent Cloud and `mdc-*` environments.

- **`broker health` is the "is it the cluster?" check.** One digest of the broker containers that are down (stopped,
  starting, fenced), the partitions that are under-replicated, under `min.insync.replicas` (acks=all producers get
  `NotEnoughReplicasException`) or without leader, and the KRaft quorum (lag and last caught up time of each node, from
  `kafka-metadata-quorum describe --replication`). It exits with 1 when something is wrong, so a script can wait for a
  healthy cluster with `--wait-healthy --max-wait 120`. A topic whose replication factor is lower than
  `min.insync.replicas` is reported as a ⚠️ warning only: it is a config problem, not a broker one.
- **`stop`, `start` and `rolling-restart` drive the broker containers.** `stop` is a controlled shutdown (the leaders
  move first), `stop --kill` a crash: the broker stays registered until its session times out, `health` reports it
  as stopped right away. `start` waits for the broker to be registered and for the cluster to be healthy again.
  `rolling-restart` refuses to start on an unhealthy cluster (`--force`), then restarts the brokers one by one and
  waits for a healthy cluster before the next one. They need several brokers (`playground run
  --enable-multiple-brokers`: ids 1, 2 and 3) to keep the cluster available, and are not available on CFK. With
  `--enable-multiple-brokers`, the internal topics of the playground (`connect-offsets`, `__consumer_offsets`…) have one
  replica: stopping a broker makes some of their partitions unavailable, `health` shows which.
- **`transactions` wraps `kafka-transactions`.** An open transaction holds the last stable offset (LSO) of its
  partitions: `read_committed` consumers don't read past it until it commits, aborts or reaches `transaction.timeout.ms`.
  `describe-producers --topic <t>` shows the start offset of each open transaction (⚠️), `find-hanging` the
  transactions that their coordinator forgot (they never end on their own; it prints the `abort` command of each), and
  `abort --topic <t> --partition <p> --start-offset <o>` ends one.
- **`describe` and `metrics` answer "what is this cluster?" and "is it the bottleneck?".** `describe`: brokers
  (endpoint, rack, fenced, container), active controller, voters and observers, feature levels (`metadata.version`…),
  and with `--api-versions` the API versions a broker supports (old clients and `UnsupportedVersionException`).
  `metrics`: one column per broker with the key JMX metrics (request handler and network processor idle, request queue,
  produce and fetch p99, bytes in and out, ISR shrinks, failed requests), read with `kafka-jmx` in the broker container.

The example [`other/broker-health-and-transactions`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/broker-health-and-transactions)
runs all of them on 3 brokers: a crash and a restart, a rolling restart, and an open transaction that blocks
`read_committed` consumers until it is aborted.

```bash
playground broker stop --broker 2
playground broker health; echo "exit=$?"
# 🩺 Health of the cluster
# 🖥️ registered brokers: 1,3
# ❌ broker 2 (container broker2) is not registered: it is stopped (playground broker start --broker 2)
# ❌ 61 under-replicated partitions
# TOPIC     PARTITION  LEADER  REPLICAS  ISR
# orders    0          1       1,2,3     1,3
# …
# ❌ cluster is not healthy: brokers down: 2, 61 under-replicated partitions, 57 unavailable
# exit=1
playground broker start --broker 2
# ✅ broker 2 is registered, waiting for its replicas to be back in sync
# ✅ cluster is healthy, broker 2 started in 11s
playground broker transactions describe-producers --topic orders
# PARTITION  PRODUCER_ID  EPOCH  COORDINATOR_EPOCH  LAST_SEQUENCE  LAST_TIMESTAMP  OPEN_TRANSACTION_START_OFFSET
# 0          7000         0      -1                 692            1793292495687   0 ⚠️
```

---

## 8. Hands-on lab (≈10 min)

```bash
playground start-environment --environment plaintext
```

**Step 1: create, and create again**

```bash
playground topic create -t lab-orders --nb-partitions 3 --config retention.ms=600000
# 🆕 Creating topic lab-orders
# Created topic lab-orders.
playground topic create -t lab-orders; echo "exit=$?"
# ❌ topic lab-orders already exist !
# exit=1
```

**Step 2: what the topic looks like**

```bash
playground topic describe -t lab-orders
# 🔎 Describing topic lab-orders
# Topic: lab-orders	TopicId: …	PartitionCount: 3	ReplicationFactor: 1	Configs: min.insync.replicas=1,retention.ms=600000
playground topic create -t connect-lab --nb-partitions 1
playground topic list
# 🔘 List of topics (internal topics are excluded)
# filestream
# lab-orders                                       <- connect-lab is not listed: "connect-" counts as internal
playground topic list --show-internal
# 🫥 List of topics (internal topics are included)
# __cluster_metadata … _schemas  connect-configs  connect-lab  connect-offsets  connect-status  filestream  lab-orders
```

**Step 3: records, counts and offsets**

```bash
playground topic produce -t lab-orders --nb-messages 10 --key 'k%g' --value '{"id": %g}'
playground topic get-number-records -t lab-orders
# 💯 Get number of records in topic lab-orders
# 10
playground topic get-offsets -t lab-orders
# PARTITION  EARLIEST  LATEST  RECORDS: 0 0 2 2 / 1 0 5 5 / 2 0 3 3 / TOTAL 10    <- keys k1…k10 spread by hash
playground topic get-size -t lab-orders
# SIZE       PARTITIONS TOPIC
# 365 B      3          lab-orders
```

**Step 4: a config that breaks a producer, then back**

```bash
playground topic alter -t lab-orders --add-config max.message.bytes=1000
# 🪛 Altering topic lab-orders
# Completed updating config for topic lab-orders.
playground topic describe -t lab-orders
# … Configs: min.insync.replicas=1,retention.ms=600000,max.message.bytes=1000
playground topic produce -t lab-orders --nb-messages 1 --record-size 5000 < scripts/cli/predefined-schemas/avro/lead.avsc
# ERROR Error when sending message to topic lab-orders with key: null, value: 3016 bytes with error: …
# org.apache.kafka.common.errors.RecordTooLargeException: The request included a message larger than the max message size the server will accept.
# ❌ 1 record(s) could not be sent to topic lab-orders: org.apache.kafka.common.errors.RecordTooLargeException: …   <- exit 1
playground topic alter -t lab-orders --delete-config max.message.bytes
```

**Step 5: waiting for records that come, and records that don't**

```bash
playground topic wait-for-records -t lab-later --min-expected-messages 1 --max-wait 10; echo "exit=$?"
# ⏳ Waiting up to 10 seconds for topic lab-later to contain at least 1 records
# ❌ topic lab-later contains 0 records after 10 seconds, expected at least 1
# exit=1
(sleep 5; playground topic produce -t lab-later --nb-messages 3 --value 'x%g') &
playground topic wait-for-records -t lab-later --min-expected-messages 3 --max-wait 60
# ✅ topic lab-later contains 3 records (expected at least 3) after … seconds
```

**Step 6: delete, subjects included**

```bash
playground topic produce -t lab-avro --nb-messages 2 < scripts/cli/predefined-schemas/avro/customer.avsc
playground schema get --subject lab-avro-value              # 🔰 subject lab-avro-value 💯 version 1 …
playground topic delete -t lab-avro
# ❌ Deleting topic lab-avro
# 🔰 Delete subject lab-avro-value
playground schema get --subject lab-avro-value; echo "exit=$?"
# ❌ No schema found !
# exit=1
playground topic delete -t 'lab-.*'
# ✨ --topic is treated as regex. Matching topics:
# lab-later
# lab-orders
playground topic delete -t lab-nope; echo "exit=$?"
# ❌ topic lab-nope does not exist and regex does not match any topic !
# exit=0
```

**Step 7: dynamic broker config, without restart**

```bash
playground broker config set --key log.retention.ms --value 60000
# ⚙️ Setting log.retention.ms=60000 cluster-wide
# BROKER   VALUE                SOURCE
# 1        60000                DYNAMIC_DEFAULT_BROKER_CONFIG
playground broker config set --key broker.id --value 3; echo "exit=$?"
# … Cannot update these configs dynamically: Set(broker.id)
# exit=1
playground broker config delete --key log.retention.ms
# BROKER   VALUE                SOURCE
# 1        (not set)            -                     <- log.retention.hours gives the value
```

**Step 8: the health and the shape of the cluster**

```bash
playground broker health; echo "exit=$?"
# 🩺 Health of the cluster
# ✅ all brokers are registered: 1
# ✅ no under-replicated partition
# …
# 🗳️ KRaft quorum: leader is node …
# ✅ cluster is healthy
# exit=0
playground broker describe
# 🖥️ Brokers (CP …)
# ID  ENDPOINT     RACK  FENCED  CONTAINER
# 1   broker:9092  null  false   broker
# 🗳️ KRaft
# 🏷️ Features
playground broker transactions list --pattern 'lab-.*'
# 🤷 no transaction found matching the filters
playground broker metrics
# 📈 Broker metrics
# METRIC                       BROKER 1
# Partitions                   …
# Under-replicated partitions  0
```

```bash
playground stop
```

---

## 9. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "`RecordTooLargeException` / `MESSAGE_TOO_LARGE`" | `topic alter -t <t> --add-config max.message.bytes=<small>`, then produce bigger records (`topic produce --record-size`); the producer side is `max.request.size` |
| "the sink lost data: retention" | `topic create … --config retention.ms=60000 --config segment.ms=10000`, produce, wait for the log cleaner, `topic get-offsets`: `EARLIEST` moved |
| "compacted topic, the sink sees old values" | `topic create … --config cleanup.policy=compact --config segment.ms=10000 --config min.cleanable.dirty.ratio=0.01`, produce the same keys several times, roll a segment, compare `get-offsets` and `consume --count` over time |
| "records of one key arrive out of order after adding partitions" | a key goes to `hash(key) % partitions`: produce keyed records on 1 partition, re-create with 3 (`topic produce --nb-partitions 3` on an empty topic, or `kafka-topics --alter --partitions` through `container exec`), produce the same keys: they move |
| "the count doesn't match what the consumer reads" | `get-number-records` (offsets) vs `topic consume --count` (records): transactions, compaction or retention explain the gap |
| "a source connector created nothing" | `topic wait-for-records -t <t> --min-expected-messages 1 --max-wait 120` (works before the topic exists), then `topic consume` |
| "our topic has an odd config" | `topic describe -t <t>`: `Configs:` shows only the overrides; compare with the customer's `kafka-configs --describe` |
| "it only happens with the broker setting of the customer" (`log.retention.ms`, `message.max.bytes`, `min.insync.replicas`, `log.cleaner.threads`…) | `playground broker config set --key <k> --value <v>` changes it on the running brokers, without restart; `broker config get --key <k>` shows the value each broker uses and where it comes from (`DYNAMIC_DEFAULT_BROKER_CONFIG`, `STATIC_BROKER_CONFIG`, `DEFAULT_CONFIG`). A key that isn't dynamic (`Cannot update these configs dynamically`) needs `container set-environment-variables` (recreates the broker) |
| "start the repro from scratch" | `topic delete -t 'repro-.*'` (subjects included), or `--skip-delete-schema` to keep the schema history |
| "which topics fill the disk?" | `topic list --sort-by-size` |
| "the client fails / pauses when a partition leader moves (`NOT_LEADER_OR_FOLLOWER`, metadata refresh)" | `playground run --enable-multiple-brokers`, `topic create -t <t> --nb-partitions 3 --replication-factor 3`, then while the client runs: `topic elect-leader -t <t> --partition 0 --leader 2` (a leader change without stopping a broker) |
| "connector errors, duplicates or a rebalance when a broker goes down" | `playground run --enable-multiple-brokers`, `topic create -t <t> --replication-factor 3`, then while the connector runs: `broker stop --broker 2` (`--kill` for a crash), `broker health`, `broker start --broker 2`; `connector status` and `container logs -c connect --errors` in between |
| "it only happens during a rolling upgrade / restart of the brokers" | `playground run --enable-multiple-brokers`, start the load, `broker rolling-restart` (one broker at a time, waits for a healthy cluster in between), then compare what the sink received. Example: `other/broker-health-and-transactions` |
| "the lag of a `read_committed` sink never drains / an exactly-once source is stuck" | `broker transactions describe-producers --topic <t>` (an open transaction holds the LSO: `OPEN_TRANSACTION_START_OFFSET` ⚠️), `broker transactions find-hanging --topic <t>`, then `broker transactions abort --topic <t> --partition <p> --start-offset <o>`. Example: `other/broker-health-and-transactions` |
| "`NotEnoughReplicasException` with acks=all" | `broker health`: under min ISR partitions, or the ⚠️ of a topic whose replication factor is lower than `min.insync.replicas` (`broker config get --key min.insync.replicas`) |
| "an old client fails with `UnsupportedVersionException`" | `broker describe --api-versions --broker 1`: the versions of each API the broker supports, and the one the tools' client picks |
| "is the broker the bottleneck of the connector?" | `broker metrics` (`--topic <t>`) during `connector benchmark`: request handler / network processor idle below 30% ⚠️, request queue size, produce p99 |
| "something goes wrong during a partition reassignment / a rebalance" | `topic reassign -t <t> --replicas 2,3 --throttle 100000 --no-wait` (slow move: under-replicated partitions while it runs), follow with `--verify-only`; `--brokers 1,2,3` spreads the partitions like a rebalance; then `topic elect-leader -t <t>` (preferred leaders). Example: `other/topic-reassign-and-leader-election` |

In a repro model, create the topics the scenario depends on **before** the producers and connectors, so their
partitions and configs are the ones of the case, not the broker's defaults:

```bash
playground topic create -t orders --nb-partitions 6 --config cleanup.policy=compact --config min.insync.replicas=1
playground topic produce -t orders --nb-messages 100 --key 'order-%g' --value '{"id": %g}'
```

---

## 10. Cheat sheet

```bash
playground topic create -t <t> [--nb-partitions N] [--config k=v]... [--replication-factor N] [--verbose]
playground topic alter -t <t> --add-config k=v[,k2=v2] | --delete-config k
playground topic describe [-t <t>] [--verbose]
playground topic list [--show-internal] [--sort-by-size]
playground topic get-size [-t <t>] [--show-internal]
playground topic get-number-records [-t <t>]
playground topic get-offsets [-t <t>]
playground topic wait-for-records -t <t> [--min-expected-messages 1] [--max-wait 120] [--interval 5]
playground topic delete -t <t|regex> [--skip-delete-schema] [--verbose]
playground topic reassign -t <t> --replicas 2,3 [--partition N] | --brokers 1,2,3 [--throttle <bytes/s>] [--dry-run] [--no-wait]
playground topic reassign -t <t> --verify-only          # progress of a --no-wait reassignment
playground topic elect-leader -t <t> [--partition N] [--leader <broker> | --unclean]
playground topic display-consumer-offsets              # follows, ctrl-c
playground broker config get [--broker <id>] [--key <k> | --all]
playground broker config set --key <k> --value <v> [--broker <id>]   # cluster-wide without --broker
playground broker config delete --key <k> [--broker <id>]
playground broker health [--wait-healthy] [--max-wait 120] [--json]     # exit 1 when not healthy
playground broker stop --broker <id> [--kill]
playground broker start --broker <id> [--max-wait 180] [--no-wait]
playground broker rolling-restart [--brokers 3,2,1] [--max-wait 300] [--force]
playground broker transactions list [--state Ongoing] [--pattern <regex>]
playground broker transactions describe --transactional-id <id>
playground broker transactions describe-producers -t <t> [--partition N]
playground broker transactions find-hanging [--broker <id> | -t <t> [--partition N]] [--max-transaction-timeout 15]
playground broker transactions abort -t <t> --partition N --start-offset <o>
playground broker describe [--api-versions [--broker <id>]]
playground broker metrics [--broker <id>] [--topic <t>] [--json]
playground topic tag list|create|delete|add|remove|show|search   # Confluent Cloud
```

- Thin wrappers around `kafka-topics` / `kafka-configs`: unknown arguments are passed through.
- `get-number-records` = offsets. `topic consume --count` = records.
- Internal = starts with `_` or `connect-`.
- `delete` hard-deletes `<topic>-key` / `<topic>-value`; `--topic` is a regex when no exact match; no match = exit 0.
- `create` fails on an existing topic; `alter` creates a missing one.
- `broker stop` / `start` / `rolling-restart` / `metrics` drive the broker containers: not on CFK. `broker health`
  and `find-hanging` exit 1 when they find a problem.
- `reassign` / `elect-leader` need several brokers (`--enable-multiple-brokers`: ids 1, 2, 3), not on Confluent Cloud. A reassignment only moves the leader when the old one leaves the replicas: `elect-leader` moves the others.
- Sources: [`commands/topic/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/topic),
  [`commands/broker/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/broker),
  [`get-topic-list.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/get-topic-list.sh).

---

**Links**

- 🎬 Video session: [🪛 A producer gets RecordTooLargeException](/sessions?id=🪛-a-producer-gets-recordtoolargeexception)
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md), [`topic consume`](/deep-dive-topic-consume.md),
  [Schema Registry](/deep-dive-schema.md) (the subjects `delete` removes),
  [offsets and lag](/deep-dive-offsets-and-lag.md) (consumer groups)
- 📖 Confluent docs: [topic configurations](https://docs.confluent.io/platform/current/installation/configuration/topic-configs.html)
- 🧠 CLI reference: [playground topic](/playground%20topic), [playground topic create](/playground%20topic%20create),
  [playground topic alter](/playground%20topic%20alter), [playground topic delete](/playground%20topic%20delete),
  [playground topic wait-for-records](/playground%20topic%20wait-for-records)
