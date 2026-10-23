# 🍪 Deep dive: offsets and lag (`connector show-lag`, `connector offsets`, `consumer-group`)

The commands that tell you **where a connector is in its data**, and move it: follow the lag of a sink until it
reaches 0, read the offsets of a source or a sink, rewind them, skip a poison record, or start over. They work the
same on self-managed and fully managed connectors, and stop / resume the connector for you when the offsets change.
Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
> first: it uses `connector show-lag` to tell a stuck sink from a slow one. This page goes further: how the commands
> work under the hood, their gotchas, a hands-on lab and recipes for support repros.

| You want | Command |
| --- | --- |
| to follow the lag of a sink until it reaches 0 | `playground connector show-lag --connector <c>` (`--interval 5`, `--max-wait 120`) |
| the offsets of a source or a sink | `playground connector offsets get --connector <c>` |
| to move them to a given point | `playground connector offsets alter --connector <c>` (edit, save, close) |
| to start over from the beginning | `playground connector offsets reset --connector <c>` |
| the lag, members or state of any consumer group | `playground consumer-group describe --group <g>` (`--members`, `--state`) |
| to rewind a consumer group to a date, by N records… | `playground consumer-group reset-offsets --group <g> --to-datetime …` (`--shift-by -100`, `--dry-run`) |
| to forget a group, or its offsets for one topic | `playground consumer-group delete --group <g>` (`--topic <t>`) |
| the raw commits in `__consumer_offsets` | `playground topic display-consumer-offsets` |

---

## 1. Mental model (the 3 things to remember)

1. **Sink offsets and source offsets are two different things.**

   | | Sink connector | Source connector |
   | --- | --- | --- |
   | Position in | the Kafka topics it consumes | the external system it reads (file position, binlog, SCN, LSN, a timestamp…) |
   | Stored in | the consumer group `connect-<connector>` (`connect-<lcc-id>` when fully managed) | the worker's `offset.storage.topic` (`connect-offsets` in the playground), keyed by connector |
   | Looks like | `{"partition": {"kafka_topic": "orders", "kafka_partition": 0}, "offset": {"kafka_offset": 5}}` | whatever the connector defines: `{"partition": {"filename": "/tmp/in.txt"}, "offset": {"position": 71}}` for FileStream |
   | Lag | yes: log end offset − committed offset | no lag in Kafka terms: `show-lag` skips sources |

   `connector offsets get|alter|reset` hide that difference behind the KIP-875 REST API. `consumer-group` and
   `show-lag` only see the sink side.

2. **Offsets only change while the connector is stopped.** The KIP-875 API refuses to change the offsets of a running
   connector, and Kafka refuses to reset a consumer group that has active members. `connector offsets alter|reset` do
   `connector stop` → change → `connector resume` for you. `consumer-group reset-offsets|delete` don't: on the group of
   a running sink they fail, and the error tells you to use `connector offsets` instead.

   Versions: `offsets get` needs CP 7.5, `alter` and `reset` CP 7.6. On an older CP, a **sink** falls back to
   `kafka-consumer-groups` (alter exports the offsets as CSV, opens it in your editor, then `--reset-offsets
   --from-file`); a **source** can't be changed.

3. **Committed is not processed.** The lag and the offsets are what the connector has **committed**, not what it
   has written. A sink commits every `offset.flush.interval.ms` (60 s by default, the playground doesn't change it),
   and a source flushes its offsets on the same schedule. Right after the data landed, `show-lag` can still show a lag
   and `offsets get` an old position (or `"offsets": []` for a new source) for up to a minute. After a crash, the connector resumes from
   the last commit: what was processed since is processed again (duplicates, not loss).

---

## 2. `connector show-lag`: is the sink catching up?

```bash
# refreshes every 20 s until the total lag is 0 (ctrl-c to stop)
playground connector show-lag --connector filestream-sink

# faster refresh, and give up after 2 minutes
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 120

# every sink connector, one after the other
playground connector show-lag
```

What it prints, per partition, with the trend since the previous check:

```text
🐢 consumer lag for 🌎onprem connector filestream-sink is 20
topic: filestream partition: 0   current-offset: 5          end-offset: 25         lag: 20         [🔹🔹🔹🔹💠💠💠💠💠💠💠💠💠💠💠💠💠💠💠💠]  20%
🔸🐌 consumer lag for 🌎onprem connector filestream-sink is still 20 🔸 (press ctrl-c to stop)
topic: filestream partition: 0   current-offset: 5          end-offset: 25         lag: 20         [🔹🔹🔹🔹💠💠💠💠💠💠💠💠💠💠💠💠💠💠💠💠]  20% 🔸
🏁 consumer lag for 🌎onprem connector filestream-sink is 0 ! took: 0min 35sec
topic: filestream partition: 0   current-offset: 25         end-offset: 25         lag: 0          [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹] 100% 🏁
```

Gotchas:

- **It only reads committed offsets** (`kafka-consumer-groups --describe --group connect-<c>`): see mental model #3.
  A lag that stays at the same value (🔸 `is still`) for **more than a minute** while the connector is RUNNING means
  stuck tasks. Under a minute, it's usually the commit interval: above, the 20 records were written within a second of
  the resume, and the lag only dropped to 0 at the next commit, 35 s later.
- **It waits for the connector to be RUNNING first**, with a RUNNING task (60 s of checks; about 80 s in practice). A
  paused or failed connector ends with `❌ … instance is not in ✅ RUNNING state after 60s` (exit 1), whatever
  `--max-wait`: resume or fix it before looking at the lag.
- **`--max-wait` is not an assertion**: when the lag is not 0 after `--max-wait` seconds it logs
  `🐢 the consumer lag is still not 0 after N seconds.` and exits **0**. In a script, check the lag with
  `consumer-group describe` or the data with `topic consume --min-expected-messages`.
- `lag: -` means the group has not committed anything yet on that partition (`🐢 consumer lag … is not available`).
- A rebalance (`Warning: Consumer group … is rebalancing`) is shown and retried at the next interval.
- Source connectors are skipped: `⏭️ Skipping source … connector …, it must be a sink to show the lag`.
- Fully managed: the group is `connect-<lcc-id>`, read with the cluster's API key from `.ccloud/`.

---

## 3. `connector offsets`: get, alter, reset

```bash
playground connector offsets get --connector filestream-sink
playground connector offsets alter --connector filestream-sink     # opens the offsets json in your editor
playground connector offsets reset --connector filestream-sink     # starts over: everything is reprocessed
```

`get` on a sink:

```json
{
  "offsets": [
    { "partition": { "kafka_partition": 0, "kafka_topic": "filestream" }, "offset": { "kafka_offset": 5 } }
  ]
}
```

What happens behind each subcommand (self-managed, CP 7.6+):

| Subcommand | REST calls | Around it |
| --- | --- | --- |
| `get` | `GET /connectors/<c>/offsets` | nothing: works on a running connector |
| `alter` | `GET …/offsets`, your edit, `PATCH …/offsets` | `connector stop` before the `PATCH`, `connector resume` after, then `get` |
| `reset` | `DELETE /connectors/<c>/offsets` | `connector stop` before, `connector resume` after, then `get` |

Gotchas:

- **`alter` is interactive**: it opens the file with the editor of `playground config get editor` and waits until
  you close it (`code --wait` for VS Code). Edit the `offset` objects, keep the `partition` objects as they are.
  `code` is started with `--wait` for you; any other GUI editor must block until you're done, or the file is applied
  unchanged.
- **A sink reset re-consumes from the earliest offset**: the group's offsets are deleted, so the consumer falls back
  to `auto.offset.reset` (`earliest` for Connect sinks). Expect duplicates downstream unless the target is
  idempotent (upsert, `insert.mode=upsert`, a key-based object name…).
- **A source reset re-reads the origin from its own beginning**, whatever that means for the connector: the whole
  file for FileStream, a new snapshot for a CDC connector (depending on `snapshot.mode`; Debezium also keeps a schema
  history topic that a reset doesn't touch).
- In a sink `alter`, an `"offset": null` for a partition resets that partition only (KIP-875).
- Source offsets are **the connector's own format**: read them with `get` before writing them, and change only the
  values (a position, a SCN), never the keys.
- **Fully managed**: same commands, through the Confluent Cloud offsets API. Changes are **asynchronous**: `alter`
  and `reset` post a `PATCH` / `DELETE` request, wait, print `connector offsets get-offsets-request-status`, then the
  offsets. No `connector stop` (not available for fully managed connectors): Confluent Cloud handles it.

---

## 4. `consumer-group`: any group, and the sink's group when it's stopped

```bash
playground consumer-group list --state
playground consumer-group describe --group connect-filestream-sink            # offsets + lag per partition, total lag
playground consumer-group describe --group my-app --members                  # who consumes what

# rewind: exactly one of --to-earliest, --to-latest, --to-offset, --to-datetime, --shift-by, --by-duration
playground consumer-group reset-offsets --group my-app --topic orders --shift-by -100 --dry-run
playground consumer-group reset-offsets --group my-app --to-datetime 2026-10-20T08:00:00.000
playground consumer-group reset-offsets --group my-app --by-duration PT1H     # one hour ago

playground consumer-group delete --group my-app                              # the whole group
playground consumer-group delete --group my-app --topic orders               # only its offsets on orders
```

Gotchas:

- **The group must have no active member.** On a running sink:
  `❌ Failed to reset offsets of consumer group connect-filestream-sink: …inactive…`, followed by
  `connect-filestream-sink is the group of sink connector filestream-sink: use playground connector offsets reset|alter --connector filestream-sink, it stops and resumes the connector for you`.
- **A stopped sink's group is inactive**: `connector stop`, then `consumer-group reset-offsets --group connect-<c>`,
  then `connector resume` is how you rewind a sink **to a date** or **by N records**, which the KIP-875 API can't do
  (it only takes explicit offsets).
- `reset-offsets` changes the offsets right away (`--execute`). `--dry-run` prints the new offsets and changes
  nothing.
- Without `--topic`, every topic of the group is reset (`--all-topics`). `--topic orders:0,2` limits it to
  partitions.
- `--to-datetime` without a time zone is read in the time zone of the JVM running the tool, the container's (UTC):
  add an offset to be sure (`2026-10-20T08:00:00.000+02:00`).
- `kafka-consumer-groups` exits 0 on errors (unknown group, active group): these commands read its output and exit 1
  instead, so they are safe in `set -e` scripts. Resetting a group that has no committed offset and no `--topic`
  fails with `⚠️ nothing to reset`.
- **`topic display-consumer-offsets` follows `__consumer_offsets` and never returns** (ctrl-c). Not available on
  Confluent Cloud.

---

## 5. Hands-on lab (≈15 min)

Start the FileStream sink example: it produces 5 records to `filestream` and creates the `filestream-sink`
connector, which writes them to `/tmp/output.json` in the `connect` container.

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh
```

**Step 1: lag and offsets of a sink**

```bash
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90
# 🏁 consumer lag for 🌎onprem connector filestream-sink is 0 ! took: 0min 1sec
# topic: filestream partition: 0   current-offset: 5   end-offset: 5   lag: 0   [🔹🔹🔹…] 100% 🏁
playground connector offsets get --connector filestream-sink
# "offset": { "kafka_offset": 5 }
playground consumer-group describe --group connect-filestream-sink
# 🏁 Total lag for consumer group connect-filestream-sink: 0
```

**Step 2: a paused sink has no lag to show**

```bash
playground connector pause --connector filestream-sink
playground topic produce -t filestream --nb-messages 20 --value '{"id": %g}'
playground consumer-group describe --group connect-filestream-sink
# connect-filestream-sink filestream  0  5  25  20  connector-consumer-filestream-sink-0-…    <- the member is still there
# 🐢 Total lag for consumer group connect-filestream-sink: 20
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 30
# 🔥 ❌ 🌎onprem connector filestream-sink instance is not in ✅ RUNNING state after 60s     <- exit 1, after ~80 s
playground connector resume --connector filestream-sink
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90
# 🐢 consumer lag … is 20, then 🔸🐌 … is still 20 🔸 (x4), then
# 🏁 consumer lag for 🌎onprem connector filestream-sink is 0 ! took: 0min 35sec       <- the next commit
```

**Step 3: the group of a running sink can't be reset from outside**

```bash
playground consumer-group reset-offsets --group connect-filestream-sink --to-earliest
# 🔥 ❌ Failed to reset offsets of consumer group connect-filestream-sink: Assignments can only be reset if the group
#       'connect-filestream-sink' is inactive, but the current state is Stable.
# 🔥    connect-filestream-sink is the group of sink connector filestream-sink: use playground connector offsets reset|alter
#       --connector filestream-sink, it stops and resumes the connector for you
```

**Step 4: reset = everything again**

```bash
playground connector offsets reset --connector filestream-sink
# 🛑 Stopping … { "message": "The offsets for this connector have been reset successfully" } … ⏯️ Resuming …
# { "offsets": [] }
playground container exec --container connect --command "wc -l /tmp/output.json"
# 50 /tmp/output.json                   <- 25 records, then the same 25 again
```

**Step 5: rewind by N records, the stopped-group way**

```bash
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90   # wait for the commit at 25 (lag: - until then)
playground connector stop --connector filestream-sink
playground consumer-group reset-offsets --group connect-filestream-sink --topic filestream --shift-by -3 --dry-run
# GROUP                   TOPIC           PARTITION  NEW-OFFSET
# connect-filestream-sink filestream      0          22
# 🧪 Nothing was changed, run again without --dry-run to apply
playground consumer-group reset-offsets --group connect-filestream-sink --topic filestream --shift-by -3
# ✅ Offsets of consumer group connect-filestream-sink reset
playground connector resume --connector filestream-sink
playground container exec --container connect --command "wc -l /tmp/output.json"
# 53 /tmp/output.json                   <- the last 3 records again
```

**Step 6: offsets of a source**

```bash
playground container exec --container connect --command "bash -c 'seq -f line-%g 1 10 > /tmp/lab-source.txt'"
playground connector create-or-update --connector filestream-source << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
  "topic": "lab-source",
  "file": "/tmp/lab-source.txt",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF
playground topic consume -t lab-source --min-expected-messages 10 --timeout 60
playground connector offsets get --connector filestream-source
# { "offsets": [] }                      <- nothing flushed yet: wait a minute
playground connector offsets get --connector filestream-source
# "partition": { "filename": "/tmp/lab-source.txt" }, "offset": { "position": 71 }   <- bytes read: 10 lines, 71 bytes
playground connector show-lag --connector filestream-source
# ⏭️ Skipping source … connector filestream-source, it must be a sink to show the lag
```

Then `playground connector offsets alter --connector filestream-source`, set `"position": 63` (the start of
`line-10`), save and close: after the resume, `line-10` is sent again (`topic consume -t lab-source --count` → 11).
`playground connector offsets reset --connector filestream-source` re-reads the whole file (→ 21).

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Commands |
| --- | --- |
| "replay the sink from yesterday 8:00" | `connector stop`, `consumer-group reset-offsets --group connect-<c> --to-datetime 2026-10-22T08:00:00.000+02:00 --dry-run`, then without `--dry-run`, `connector resume` |
| "one record crashes the sink, skip it" | `topic consume --partition <p> --offset <o> --max-messages 1` to see it, then `connector offsets alter`: set that partition's `kafka_offset` to `<o>+1` (or use `errors.tolerance=all` + a DLQ) |
| "re-snapshot / re-read the source from the start" | `connector offsets reset --connector <c>` (CDC: check `snapshot.mode` and the schema history topic too) |
| "move a CDC source back to a SCN / LSN / binlog position" | `connector offsets get` to see the connector's format, `connector offsets alter` to change the value |
| "lag never goes to zero" | `show-lag --interval 10`: 🔸 same value = stuck tasks (`connector diagnose`, a thread dump), 🔻 slowly = throughput (`connector benchmark`), stuck at a small value right after the data landed = not committed yet (wait `offset.flush.interval.ms`) |
| "the sink reprocessed everything after a rename" | the group name follows the connector name (`connect-<new name>`): the new group starts from `auto.offset.reset`. `consumer-group list` shows both |
| "my app's consumer group is stuck / needs a rewind" | `consumer-group describe --group <g> --members`, stop the app, `consumer-group reset-offsets --group <g> … --dry-run` |
| "duplicates after a crash" | expected: at-least-once from the last commit. Lower `offset.flush.interval.ms` to narrow the window, make the target idempotent |

---

## 7. Cheat sheet

```bash
playground connector show-lag [--connector <c>] [--interval 20] [--max-wait 0]
playground connector offsets get|alter|reset [--connector <c>]          # alter: edit in $(playground config get editor)
playground connector offsets get-offsets-request-status --connector <c> # fully managed only
playground connector stop|resume --connector <c>
playground consumer-group list [--state]
playground consumer-group describe [--group <g>] [--members|--state]
playground consumer-group reset-offsets --group <g> [--topic <t>[:p,p]] \
  --to-earliest|--to-latest|--to-offset N|--to-datetime <date>|--shift-by ±N|--by-duration PT1H [--dry-run]
playground consumer-group delete --group <g> [--topic <t>]
playground topic display-consumer-offsets                               # follows, ctrl-c
```

- Sink = consumer group `connect-<c>`. Source = connector-specific map in `connect-offsets`.
- Offsets change only on a stopped connector: `connector offsets alter|reset` stop and resume it for you.
- `get` CP 7.5+, `alter` / `reset` CP 7.6+ (older CP: sinks only, through `kafka-consumer-groups`).
- Lag and offsets are **committed** values: up to `offset.flush.interval.ms` (60 s) behind.
- `show-lag --max-wait` exits 0 even when the lag isn't 0.
- Sources: [`connector/show-lag.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/show-lag.sh),
  [`connector/offsets/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/connector/offsets),
  [`consumer-group/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/consumer-group).

---

**Links**

- 🎬 Video session: [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
- 🍪 Deep dive: [`topic consume`](/deep-dive-topic-consume.md), to look at the record behind an offset
- 💡 [Check Kafka Connect offsets](/tips-and-tricks?id=check-kafka-connect-offsets) in Tips & Tricks
- 📖 KIP-875 offsets API: [Confluent Cloud connector offsets](https://docs.confluent.io/cloud/current/connectors/offsets.html)
- 🧠 CLI reference: [playground connector show-lag](/playground%20connector%20show-lag),
  [playground connector offsets](/playground%20connector%20offsets), [playground consumer-group](/playground%20consumer-group),
  [playground connector stop](/playground%20connector%20stop)
