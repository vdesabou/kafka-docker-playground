# Kafka Streams

## Objective

A base to reproduce [Kafka Streams](https://docs.confluent.io/platform/current/streams/overview.html) support cases:
one stateful application running as 3 instances (`streams`, `streams2`, `streams3`), configured by a properties file
(drop the customer's `StreamsConfig` in), built with the Kafka Streams version of the customer, and one script per
support topic:

| Script | Topology | What it shows |
| --- | --- | --- |
| `count.sh` | `groupBy` → `count` | rebalance, an instance killed and restarted, warm-up (standby) tasks, restore from the changelog |
| `windowed.sh` | tumbling windows + grace period + `suppress` | out-of-order records within the grace period, a late record dropped (`dropped-records-total`), one final result per window |
| `join.sh` | stream-table join + foreign-key join | repartition for co-partitioning, inner join dropping unknown keys, a table update re-emitting through the foreign-key join (subscription topics), joins not being retroactive, and two topics that are not co-partitioned: refused up to Kafka Streams 3.1, silently losing join results since 3.2 |
| `eos.sh` | `count` with `processing.guarantee=exactly_once_v2` | an instance paused in the middle of a transaction (zombie), its tasks moved, fenced when it comes back, exact counts for `read_committed` consumers, the aborted records only visible to `read_uncommitted` ones |
| `serde-errors.sh` | Avro (Schema Registry) → JSON | a poison pill (deserialization exception handler), a record too large for the producer (production exception handler), schema evolution, and the default `LogAndFailExceptionHandler` stopping an application |

The application logs what matters in a Streams case: its state transitions (`CREATED`, `REBALANCING`, `RUNNING`,
`ERROR`…), the active and standby tasks of each thread when it becomes `RUNNING`, the restoration of its state stores
(`♻️ Restore started` / `✅ Restore completed`, with the number of records restored), uncaught exceptions with their
causes on one line (`💀 Uncaught exception in a stream thread of …`), and the `dropped-records-total` metric when it
changes (`🗑️`).

## How to run

```bash
playground run -f count<tab>          # or windowed, join, eos, serde-errors
```

With the Kafka Streams version of the customer (any Apache Kafka version since 3.0.0, patch included), which does not
have to match the brokers:

```bash
playground run -f eos<tab> --tag 8.2.0 --client-version 3.7.1
```

The application is built when the version changes (`streams/target/kafka-streams-app-<version>-jar-with-dependencies.jar`,
`mvn clean package`: only the jar of the last version is kept), with the Confluent Avro serde of the matching release
(7.N.0 for Apache Kafka 3.N, 8.N.0 for 4.N). An older version is skipped (`exit 111`). Only the plaintext environment is
supported for now (`exit 111` on the others).

## How it works

- `streams/`: the Java application. `TOPOLOGY` (exported by each script) selects the scenario
  (`StreamsApp`, `Scenario`, `<Name>Scenario.java`).
- `config/<scenario>.properties`: the `StreamsConfig` of each scenario, mounted in the 3 instances. `bootstrap.servers`
  comes from `STREAMS_BOOTSTRAP_SERVERS` in `docker-compose.plaintext.yml`. The keys starting with `app.` configure the
  scenario (window size, grace period, suppression buffer…) and are not passed to Kafka Streams. Client security
  settings can go in an `/etc/kafka-streams/extra.properties` file (read when it exists).
- Some scenarios also start a demo application in the same JVM, with its own `application.id`, to show a failure without
  stopping the main application: `streams-join-copartition-demo`, `streams-serde-errors-fail-on-poison-pill`.
- `streams-functions.bash`: the functions of the scripts (build, start, wait for records, counts, logs since a
  timestamp). Not a `.sh` file: CI runs every `.sh` of the folder.

## What the scripts do

### count.sh

1. 1000 records to `streams-input` (6 partitions): the latest count of each bucket in `streams-output` adds up to 1000
2. `playground consumer-group describe --group streams-count --members`: 3 members, 4 partitions each (input and
   repartition topic)
3. kills `streams2` (`playground container kill`): after the session timeout, its tasks move to `streams` and
   `streams3`, which restore the state store from the changelog topic. 1000 more records: 2000
4. restarts `streams2`. With the high availability task assignor (Kafka Streams 2.6+), it first gets standby
   (warm-up) tasks only, then its active tasks back after a follow-up rebalance, and restores their state:

   ```text
   📋 Assignment of streams-count-…-StreamThread-1: active tasks [], standby tasks [1_1, 1_4]
   ♻️ Restore started for store counts-store from streams-count-counts-store-changelog-1: offsets 0 to 6
   ✅ Restore completed for store counts-store from streams-count-counts-store-changelog-1: 6 records restored
   📋 Assignment of streams-count-…-StreamThread-1: active tasks [0_1, 0_4, 1_1, 1_4], standby tasks []
   ```

   1000 more records: 3000
5. `playground streams status` (retried until every instance is RUNNING, it exits 1 otherwise): the state of each
   instance, its rebalances and the time spent in REBALANCING, its tasks, the records restored, the restart of
   `streams2`, and the consumer group (`--html` adds a timeline of the states and the task assignment):

   ```text
   🌊 application streams-count (Kafka Streams 4.4.0): 3 instance(s)
     INSTANCE  STATE    SINCE     REBALANCES  THREADS    ACTIVE TASKS        STANDBY TASKS  NOT RESTORED
     streams   RUNNING  15:25:39  4 (3.6s)    1 RUNNING  0_2, 0_5, 1_2, 1_5  -              -
     streams2  RUNNING  15:25:39  3 (6.3s)    1 RUNNING  0_0, 0_3, 1_0, 1_3  -              -
     streams3  RUNNING  15:25:39  4 (3.3s)    1 RUNNING  0_1, 0_4, 1_1, 1_4  -              -
     ♻️ restored: streams 7 record(s) from 5 changelog partition(s), streams2 6 record(s) from 4 changelog partition(s), streams3 3 record(s) from 5 changelog partition(s)
     🔁 streams2: restarted 1 time(s) in these logs
   👥 consumer group streams-count: Stable, 3 member(s), lag 0 🏁
   ```

The restore checks only count the log lines written after the kill and after the restart (`playground container logs
--since`): container logs survive a restart.

### windowed.sh

Windows of 1 minute (`app.window.size.ms`) with a grace period of 30 seconds (`app.window.grace.ms`), the final count of
each window only (`suppress(untilWindowCloses)`). The event time is the `ts` field of the value, so the readings of
`sensor-a` land in known windows (T0 = 2026-01-01T00:00:00Z):

| Reading | Stream time | Effect |
| --- | --- | --- |
| T0, T0+10s, T0+20s | 00:00:20 | window 1 [00:00, 00:01): 3 |
| T0+70s | 00:01:10 | window 2 opens, window 1 still open (grace period until 00:01:30) |
| T0+50s | 00:01:10 | out-of-order, within the grace period: window 1: 4 |
| T0+100s | 00:01:40 | window 1 closes: `sensor-a@2026-01-01T00:00:00Z` = 4 emitted, once |
| T0+30s | 00:01:40 | late, after the grace period: dropped, `🗑️ dropped-records-total … 1`, window 1 stays at 4 |
| T0+200s | 00:03:20 | window 2 closes: `sensor-a@2026-01-01T00:01:00Z` = 2 |

`app.suppress.max.records` bounds the suppression buffer (`BufferConfig.maxRecords(n).shutDownWhenFull()`): the
application shuts down when it is full, instead of buffering in memory without limit. `app.window.retention.ms` sets the
retention of the window store (at least size + grace).

### join.sh

| Step | Result |
| --- | --- |
| customers c1, c2 (`customers`, 3 partitions), products p1, p2 (`products`, 2 partitions), then orders o1 (c1, p1), o2 (c2, p2), o3 (c3, p1) (`orders`, 6 partitions, keyed by order id) | |
| stream-table join: the orders are re-keyed by customer and repartitioned (`streams-join-orders-customers-join-repartition`) to be co-partitioned with `customers` | `orders-enriched`: o1, o2. o3 dropped (inner join, no customer c3) |
| foreign-key join of the orders table with the products table, through subscription topics (`…-KTABLE-FK-JOIN-SUBSCRIPTION-…`), no repartition of the orders by product | `orders-with-product`: o1, o2, o3 |
| p1 renamed | the foreign-key join re-emits o1 and o3 with the new name |
| customer c3 created, then order o4 of c3 | o4 joined, o3 still dropped: a stream-table join is not retroactive |
| `streams-join-copartition-demo`: `orders-by-customer` (6 partitions, already keyed by customer) joined with `customers` (3 partitions) directly | see below |

Two topics that are not co-partitioned: the result depends on the Kafka Streams version.

| Kafka Streams | copartition-demo |
| --- | --- |
| up to 3.1 (run with 3.0.0 and 3.1.0) | refused: `TopologyException: Invalid topology: … Topics not co-partitioned: [{customers=3, orders-by-customer=6}]`, the demo application goes to `ERROR` |
| since 3.2 (run with 3.2.0 and 4.4.0) | accepted: `Skipping the repartition topic validation since there are no repartition topics`. 6 tasks, tasks 3 to 5 get no partition of `customers`, and an order joins only when its key lands in the same partition number in both topics (murmur2 % 6 == murmur2 % 3): c2 (partition 1 in both) joins, c1 and c3 (partition 5 of `orders-by-customer`, partition 2 of `customers`) are lost, without error nor `dropped-records-total` |

Since 3.2, `RepartitionTopics#setup` only calls `ensureCopartitioning` when the topology has repartition topics
([apache/kafka 529dde904a](https://github.com/apache/kafka/commit/529dde904a), KAFKA-12648, #11600): a join of two
source topics with different partition counts is no longer refused. The script accepts both outcomes.

### eos.sh

The count topology with `processing.guarantee=exactly_once_v2`, `consumer.session.timeout.ms=10000` and
`producer.transaction.timeout.ms=10000` (`config/eos.properties`):

1. 1000 records: 1000 with `--isolation-level read_committed`, the transactional producers in
   `playground broker transactions list`
2. 3000 records at 100 records/s in the background, and `streams2` paused in the middle of its transactions
   (`playground container pause`): its tasks move after 10 seconds, its open transaction is aborted after 10 seconds.
   The counts add up to 4000 exactly
3. `streams2` resumed: the zombie is fenced and rejoins

   ```text
   Detected that the thread is being fenced. This implies that this thread missed a rebalance and dropped out of the consumer group.
   TaskMigratedException: Producer got fenced trying to add offsets to a transaction
   ```

4. 1000 more records: 5000. `eos-output` holds more records for `read_uncommitted` consumers than for `read_committed`
   ones (231 against 225 in one run): the records of the aborted transactions

### serde-errors.sh

Payments in Avro (Schema Registry), written as JSON to `payments-processed`:

| Record | Result |
| --- | --- |
| p1, p2 (schema v1: id, amount) | processed |
| `this is not avro` (a poison pill) | `LogAndContinueExceptionHandler`: `Exception caught during Deserialization`, skipped |
| p3 (schema v2, adds `currency` with a default: backward compatible) | processed with its own (writer) schema, `currency` included |
| inflate | the application makes it larger than `producer.max.request.size` (4096): `RecordTooLargeException`, `ContinueOnRecordTooLargeHandler` logs `📦 Production exception handler: skipping …`, skipped |

`streams-serde-errors-fail-on-poison-pill` runs the same topology with the default `LogAndFailExceptionHandler`: it stops
on the poison pill (`state transition from PENDING_ERROR to ERROR`).

## Use it in a repro

```bash
# what each instance is doing: state, rebalances, active / standby tasks, restoration, known errors, consumer group
# (exits 1 when an instance is not RUNNING; --html adds a timeline of the states and the task assignment)
playground streams status
playground streams status --application-id streams-serde-errors-fail-on-poison-pill --html
playground container logs --container streams2 --grep "state transition\|Assignment of\|Restore\|Uncaught\|dropped-records"

# replace the StreamsConfig of a scenario (config/<scenario>.properties), then restart the instances
playground container restart --container streams --container streams2 --container streams3

# rebalance, failure and network scenarios
playground container kill --container streams3
playground container pause --container streams3
playground broker rolling-restart
playground debug degrade-traffic --container streams --latency 500ms --action start

# committed offsets and lag, open transactions
playground consumer-group describe --group streams-count
playground broker transactions list --pattern streams-eos
```
