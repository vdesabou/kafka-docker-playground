# 🍪 Deep dive: brokers and transactions (`playground broker`)

The commands that look at the cluster rather than at one topic or one connector: is it healthy, what does it look
like, what happens when a broker crashes or the brokers restart one by one, which transaction is blocking a
`read_committed` consumer, and is a broker the bottleneck. They are what turns "the connector failed during the
night" into a repro: the same broker failure, on demand, while the connector runs. Takes about 20 minutes to read and
run.

> [!TIP]
> Topics themselves (create, configs, counts, reassignments, leader elections) are in the
> [topic administration deep dive](/deep-dive-topic-administration.md), and `broker config` (dynamic broker configs)
> is there too. Producing records in a transaction is a flag of [`topic produce`](/deep-dive-topic-produce.md).

| You want | Command |
| --- | --- |
| is the cluster healthy? (a broker down, under-replicated, under min ISR or offline partitions, KRaft quorum) | `playground broker health` (`--wait-healthy --max-wait 120`, `--json`; exit 1 when not healthy) |
| brokers, active controller, `metadata.version`, API versions | `playground broker describe` (`--api-versions --broker <id>`) |
| stop a broker, or crash it | `playground broker stop --broker 2` (`--kill` for a crash) |
| start it again, and wait for the cluster to be healthy | `playground broker start --broker 2` |
| restart the brokers one by one, like a rolling upgrade | `playground broker rolling-restart` (`--brokers 3,2,1`, `--force`) |
| records in a transaction that never ends | `playground topic produce -t <t> --transactional-id <id> --transaction open --transaction-timeout 900000` |
| open and hanging transactions (a `read_committed` consumer stuck) | `playground broker transactions list\|describe\|describe-producers\|find-hanging\|abort` |
| is a broker the bottleneck? (idle threads, p99 latency, bytes in/out) | `playground broker metrics` (`--topic <t>`, `--json`) |
| change a config of the live brokers | `playground broker config set --key <k> --value <v>` (see the [topic administration deep dive](/deep-dive-topic-administration.md)) |

---

## 1. Mental model (the 3 things to remember)

1. **They run next to the brokers, with the environment's credentials.** `health`, `describe` and `transactions` run
   `kafka-topics`, `kafka-metadata-quorum`, `kafka-features`, `kafka-broker-api-versions` and `kafka-transactions` in
   the broker container (the `client` container on kerberos, `connect-0` on CFK), like the topic commands, so they work
   on plaintext, the secured environments and CFK. `stop`, `start`, `rolling-restart` and `metrics` drive the broker
   **containers** (`broker`, `broker2`, `broker3` for ids 1, 2, 3): not on CFK. None of them on Confluent Cloud and
   the `mdc-*` environments. `--verbose` prints the exact command.

2. **Three brokers make the failures realistic.** `playground run --enable-multiple-brokers` starts brokers 1, 2 and 3,
   and creates the internal topics (`__consumer_offsets`, `__transaction_state`, `connect-offsets`, `connect-status`,
   `connect-configs`, `_schemas`, `_confluent-link-metadata`…) with **3 replicas and a min ISR of 2**, like in
   production: one broker can stop and nothing becomes unavailable, connectors keep running. With one broker, they
   have 1 replica, and stopping it stops the cluster. Your own topics get what you create: `topic create
   --replication-factor 3 --config min.insync.replicas=2`.

3. **An open transaction holds the last stable offset (LSO).** `read_committed` consumers (sink connectors of a topic
   written by an exactly-once source, Kafka Streams with `exactly_once_v2`, consumers with
   `isolation.level=read_committed`) don't read past the first record of an open transaction, even records produced
   after it without transaction. It ends when its producer commits or aborts it, or when the coordinator aborts it
   after `transaction.timeout.ms`. A **hanging** transaction is open on a partition but forgotten by its coordinator:
   it never ends on its own and must be aborted.

---

## 2. Is it the cluster? `health`, `describe`

```bash
playground broker health
# 🩺 Health of the cluster
# ✅ all brokers are registered: 1,2,3
# ✅ no under-replicated partition
# ✅ no under min.insync.replicas partition
# ✅ no unavailable (no leader) partition
# 🗳️ KRaft quorum: leader is node 4
# NODE  STATUS    LOG_END_OFFSET  LAG  LAST_CAUGHT_UP
# 4     Leader    1053            0    0s ago
# 1     Observer  1053            0    0s ago
# …
# ✅ cluster is healthy
playground broker describe
# 🖥️ Brokers (CP 8.4.0)
# ID  ENDPOINT      RACK  FENCED  CONTAINER
# 1   broker:9092   null  false   broker
# 2   broker2:9092  null  false   broker2
# 3   broker3:9092  null  false   broker3
# 🗳️ KRaft
# Active controller:     4 (epoch 1)
# Voters (controllers):  4
# Observers (brokers):   1,2,3
# 🏷️ Features
# FEATURE                     FINALIZED    SUPPORTED
# confluent.metadata.version  CP-8.4-IV2A  CP-7.3-IV3 to CP-8.4-IV2A
# …
```

- **`health` checks four things**: the broker containers (down: stopped, still starting, or **fenced**), the
  partitions that are under-replicated, under `min.insync.replicas` (acks=all producers get
  `NotEnoughReplicasException`) or without leader (`kafka-topics --under-replicated-partitions`,
  `--under-min-isr-partitions`, `--unavailable-partitions`), and the KRaft quorum (`kafka-metadata-quorum describe
  --replication`: lag and last caught up time of each node, ⚠️ after 30 s).
- **It exits with 1 when the cluster is not healthy**, with a one line summary, so a script can check it, or wait for
  it: `--wait-healthy --max-wait 120`. `--json` gives everything as JSON (`healthy`, `brokers`, the partitions,
  `kraft_quorum`).
- **A killed broker is down right away**, even though it stays registered until its session times out (about 9 s):
  `health` also checks that its container runs.
- **A topic whose replication factor is lower than `min.insync.replicas` is only a ⚠️ warning**: all its replicas
  are in sync, it is a config problem (acks=all producers always fail), not a broker one. A customer configuration
  can have it; a fresh playground doesn't.
- **`describe --api-versions --broker <id>`** prints the versions of each API the broker supports, and the one the
  tools' client picks (`[usable: N]`): the starting point for an old client failing with `UnsupportedVersionException`.

---

## 3. Broker failures: `stop`, `start`, `rolling-restart`

```bash
playground broker stop --broker 3 --kill
# 🔫 Killing broker 3 (container broker3): no controlled shutdown, like a crash
playground broker health; echo "exit=$?"
# ❌ broker 3 (container broker3) is stopped, still registered until its session times out (playground broker start --broker 3)
# ✅ no unavailable (no leader) partition                    <- 3 replicas: everything stays available
# ❌ cluster is not healthy: brokers down: 3
# exit=1
# … a few seconds later, once its session timed out:
# ❌ broker 3 (container broker3) is not registered: it is stopped (playground broker start --broker 3)
# ❌ 151 under-replicated partitions
# ❌ cluster is not healthy: brokers down: 3, 151 under-replicated partitions
playground broker start --broker 3
# ▶️ Starting broker 3 (container broker3)
# ✅ broker 3 is registered, waiting for its replicas to be back in sync
# ✅ cluster is healthy, broker 3 started in 11s
playground broker rolling-restart
# 🔄 [1/3] Restarting broker 1 (container broker)
# ✅ [1/3] broker 1 restarted, cluster is healthy (19s)
# …
# 🎉 rolling restart of brokers 1,2,3 done in 57s
```

- **`stop` is a controlled shutdown**: the broker moves its leaders to the other replicas before it stops, clients
  see a clean leader change. **`stop --kill` is a crash**: the leaders move only once the controller notices, clients
  see disconnections, `NOT_LEADER_OR_FOLLOWER` and retries.
- **`start` waits** for the broker to be registered (not fenced), then for the cluster to be healthy (its replicas
  back in the ISR), up to `--max-wait` (180 s). `--no-wait` just starts the container.
- **`rolling-restart` refuses an unhealthy cluster** (`--force` to restart anyway), then restarts each broker (a
  controlled shutdown) and waits for a healthy cluster before the next one. It stops at the first broker that doesn't
  come back within `--max-wait` (300 s), without touching the next ones. `--brokers 3,2,1` sets the order.
- **What a connector sees**: with 3 brokers, a running connector stays `RUNNING` through a crash and a rolling restart;
  its clients reconnect and retry. What to look at in a repro is what happens around it: duplicates (a producer retried
  after a timeout), a rebalance, a task that fails with an exception the customer has (`playground container logs -c
  connect --errors --since 10m`).
- **Settings that need a restart**: `playground container set-environment-variables` recreates the broker with the new
  environment. Dynamic ones: `playground broker config set`, no restart.

---

## 4. Transactions: `topic produce --transactional-id`, `broker transactions`

```bash
playground topic produce -t payments --nb-messages 10 --value 'in-transaction-%g' --transactional-id payments-txn --transaction open --transaction-timeout 900000
# records sent in the transaction of payments-txn: 10 {0=10}
# transaction left open, the coordinator aborts it after transaction.timeout.ms (900000 ms)
playground topic produce -t payments --nb-messages 5 --value 'after-%g'
playground topic consume --topic payments --count                                      # 15
playground topic consume --topic payments --isolation-level read_committed --count     # 0: blocked by the open transaction
playground broker transactions list --state Ongoing
# TRANSACTIONAL_ID  COORDINATOR  PRODUCER_ID  STATE
# payments-txn      2            3002         Ongoing
playground broker transactions describe-producers --topic payments
# PARTITION  PRODUCER_ID  EPOCH  COORDINATOR_EPOCH  LAST_SEQUENCE  LAST_TIMESTAMP  OPEN_TRANSACTION_START_OFFSET
# 0          3002         0      -1                 9              1793293540214   0 ⚠️
playground broker transactions find-hanging --topic payments
# ✅ no hanging transaction                                      <- its coordinator still tracks it
playground broker transactions abort --topic payments --partition 0 --start-offset 0
# ✅ transaction aborted
playground topic consume --topic payments --isolation-level read_committed --count     # 5: the aborted ones are skipped
```

- **`topic produce --transactional-id` makes the transactions**: `--transaction commit` (default), `abort` or `open`
  (the producer stops without ending it; the coordinator aborts it after `--transaction-timeout`, 60 s by default, at
  most `transaction.max.timeout.ms` of the brokers, 15 minutes). How it works: see the
  [`topic produce` deep dive](/deep-dive-topic-produce.md).
- **`describe-producers --topic <t>`** shows, for each partition, the producers that wrote to it recently and the start
  offset of their open transaction (⚠️): that offset is where `read_committed` consumers are blocked.
- **`describe --transactional-id <id>`**: state, producer id and epoch, timeout, start time, duration, and the
  partitions of the current transaction. **`list`** filters with `--state Ongoing` and `--pattern <regex>`.
- **`find-hanging`** searches every broker (or `--broker`, or the partitions of `--topic`) for transactions open for
  longer than `--max-transaction-timeout` minutes (15) that their coordinator doesn't know any more. It exits with 1
  when it finds some, and prints the `abort` command of each. An open transaction that its coordinator still tracks is
  not hanging: it ends after its timeout.
- **`abort --topic <t> --partition <p> --start-offset <o>`** writes an abort marker for the transaction started at that
  offset (administrative privileges). Its records are discarded, `read_committed` consumers move on.
- **Counting `read_committed` records**: `topic consume --isolation-level read_committed --count` reads them. `topic
  get-number-records` counts offsets up to the high watermark, aborted records and transaction markers included.

---

## 5. Is a broker the bottleneck? `metrics`

```bash
playground broker metrics --topic orders
# 📈 Broker metrics (rates and failed requests of topic orders)
# METRIC                                 BROKER 1  BROKER 2  BROKER 3
# Partitions                             58        51        54
# Leaders                                57        51        53
# Under-replicated partitions            0         0         0
# Under min ISR partitions               0         0         0
# Request handler idle (1m)              100%      100%      100%
# Network processor idle                 100%      100%      100%
# Request queue size                     0         0         0
# Produce p99                            28 ms     32 ms     19 ms
# Fetch consumer p99                     505 ms    505 ms    506 ms
# …
```

- One column per broker, read with `kafka-jmx` in each broker container (no download, about a second per broker):
  partitions and leaders, under-replicated and under min ISR partitions, request handler and network processor idle
  ratio, request queue size, produce and fetch p99, messages and bytes in and out per second (of `--topic` only, with
  it), ISR shrinks and expands, failed produce and fetch requests. `--json` for the raw values.
- **⚠️ marks the values to look at**: idle below 30% (the broker threads are saturated: `num.io.threads`,
  `num.network.threads`), under-replicated or under min ISR partitions.
- **Fetch p99 around 500 ms is normal**: a fetch waits up to `fetch.max.wait.ms` / `replica.fetch.wait.max.ms` (500
  ms) for data.
- Every metric of a broker: `playground get-jmx-metrics -c broker`.

---

## 6. Hands-on lab (≈15 min)

```bash
playground run -f other/deep-dive-labs/broker.sh     # or start the environment and run the steps by hand:
ENABLE_KAFKA_NODES=true playground start-environment --environment plaintext
```

**Step 1: the shape and the health of the cluster**

```bash
playground broker describe
# ID  ENDPOINT      RACK  FENCED  CONTAINER
# …
# 3   broker3:9092  null  false   broker3
# Observers (brokers):   1,2,3
playground broker health
# ✅ all brokers are registered: 1,2,3
# ✅ cluster is healthy                                  <- and no ⚠️ on a fresh environment
playground topic describe --topic connect-offsets      # ReplicationFactor: 3
```

**Step 2: a broker crashes**

```bash
playground topic create --topic lab-orders --nb-partitions 3 --replication-factor 3 --config min.insync.replicas=2
playground broker stop --broker 3 --kill
# 🔫 Killing broker 3 (container broker3): no controlled shutdown, like a crash
playground broker health; echo "exit=$?"
# ❌ broker 3 (container broker3) …
# ✅ no unavailable (no leader) partition
# ❌ cluster is not healthy: brokers down: 3, …
# exit=1
playground topic produce -t lab-orders --nb-messages 10 --value 'order-%g' --producer-property acks=all
# 📤 produced 10 records to topic lab-orders                <- 2 replicas in sync = min.insync.replicas
```

**Step 3: it comes back, then a rolling restart**

```bash
playground broker start --broker 3
# ✅ broker 3 is registered, waiting for its replicas to be back in sync
# ✅ cluster is healthy, broker 3 started in …s
playground broker stop --broker 3 --kill
playground broker rolling-restart; echo "exit=$?"
# ❌ cluster is not healthy before the rolling restart: brokers down: 3
# exit=1
playground broker start --broker 3
playground broker rolling-restart
# 🔄 [1/3] Restarting broker 1 (container broker)
# …
# 🎉 rolling restart of brokers 1,2,3 done in …s
```

**Step 4: an open transaction blocks read_committed consumers**

```bash
playground topic produce -t lab-payments --nb-messages 10 --value 'in-transaction-%g' --transactional-id lab-payments-txn --transaction open --transaction-timeout 900000
# transaction left open, the coordinator aborts it after transaction.timeout.ms (900000 ms)
playground topic produce -t lab-payments --nb-messages 5 --value 'after-%g'
playground topic consume --topic lab-payments --count                                    # 15
playground topic consume --topic lab-payments --isolation-level read_committed --count   # 0
playground broker transactions list --state Ongoing                                      # lab-payments-txn
playground broker transactions describe-producers --topic lab-payments
# PARTITION  PRODUCER_ID  EPOCH  COORDINATOR_EPOCH  LAST_SEQUENCE  LAST_TIMESTAMP  OPEN_TRANSACTION_START_OFFSET
# 0          …                                                                     0 ⚠️
```

**Step 5: not hanging, aborted anyway**

```bash
playground broker transactions find-hanging --topic lab-payments
# ✅ no hanging transaction
playground broker transactions abort --topic lab-payments --partition 0 --start-offset 0
# ✅ transaction aborted
playground topic consume --topic lab-payments --isolation-level read_committed --count   # 5
```

**Step 6: metrics and API versions**

```bash
playground broker metrics --topic lab-orders
# METRIC                       BROKER 1  BROKER 2  BROKER 3
# Under-replicated partitions  0         0         0
playground broker describe --api-versions --broker 2
# 🔌 API versions supported by broker 2 (min to max, [usable: N] is the version this client picks)
# 	Produce(0): 0 to 13 [usable: 13],
```

```bash
playground stop
```

---

## 7. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "connector errors, duplicates or a rebalance when a broker goes down" | `playground run --enable-multiple-brokers`, `topic create -t <t> --replication-factor 3`, then while the connector runs: `broker stop --broker 2` (`--kill` for a crash), `broker health`, `broker start --broker 2`; `connector status` and `container logs -c connect --errors` in between |
| "it only happens during a rolling upgrade / restart of the brokers" | `playground run --enable-multiple-brokers`, start the load, `broker rolling-restart` (one broker at a time, waits for a healthy cluster in between), then compare what the sink received. Example: `other/broker-health-and-transactions` |
| "`NotEnoughReplicasException` with acks=all" | `topic create … --replication-factor 3 --config min.insync.replicas=3`, `broker stop --broker 3`, produce with `--producer-property acks=all`; `broker health` shows the partitions under min ISR, or the ⚠️ of a topic whose replication factor is lower than `min.insync.replicas` |
| "the lag of a `read_committed` sink never drains / an exactly-once source is stuck" | `broker transactions describe-producers --topic <t>` (`OPEN_TRANSACTION_START_OFFSET` ⚠️ = where the consumer is blocked), `broker transactions find-hanging --topic <t>`, then `broker transactions abort --topic <t> --partition <p> --start-offset <o>`. Reproduce it with `topic produce --transactional-id <id> --transaction open`. Example: `other/broker-health-and-transactions` |
| "an old client fails with `UnsupportedVersionException`" | `broker describe --api-versions --broker 1`: the versions of each API the broker supports, and the one the tools' client picks |
| "is the broker the bottleneck of the connector?" | `broker metrics` (`--topic <t>`) during `connector benchmark`: request handler / network processor idle below 30% ⚠️, request queue size, produce p99 |
| "it happens after an upgrade of the brokers" | `broker describe`: `metadata.version` and the feature levels; `playground update-version` to move the CP version of the running environment |
| "a script must wait until the cluster recovered" | `playground broker health --wait-healthy --max-wait 300` (exit 1 on timeout) |

---

## 8. Cheat sheet

```bash
playground broker health [--wait-healthy] [--max-wait 120] [--json]     # exit 1 when not healthy
playground broker describe [--api-versions [--broker <id>]]
playground broker stop --broker <id> [--kill]
playground broker start --broker <id> [--max-wait 180] [--no-wait]
playground broker rolling-restart [--brokers 3,2,1] [--max-wait 300] [--force]
playground topic produce -t <t> … --transactional-id <id> [--transaction commit|abort|open] [--transaction-timeout <ms>]
playground broker transactions list [--state Ongoing] [--pattern <regex>]
playground broker transactions describe --transactional-id <id>
playground broker transactions describe-producers -t <t> [--partition N]
playground broker transactions find-hanging [--broker <id> | -t <t> [--partition N]] [--max-transaction-timeout 15]
playground broker transactions abort -t <t> --partition N --start-offset <o>
playground broker metrics [--broker <id>] [--topic <t>] [--json]
playground broker config get|set|delete …                              # see the topic administration deep dive
```

- `--enable-multiple-brokers` = brokers 1, 2, 3 and internal topics with 3 replicas, min ISR 2.
- `stop` / `start` / `rolling-restart` / `metrics` drive the containers: not on CFK. Nothing on Confluent Cloud, `mdc-*`.
- `health` and `find-hanging` exit 1 when they find a problem.
- `read_committed` counts: `topic consume --isolation-level read_committed --count`.
- Sources: [`commands/broker/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/broker),
  `get_cluster_health`, `run_kafka_admin_subcommand_tool`, `run_transactional_copier` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh),
  [`transactional-copier`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/transactional-copier).

---

**Links**

- 🧪 Example: [`other/broker-health-and-transactions`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/broker-health-and-transactions)
- 🍪 Deep dives: [topic administration](/deep-dive-topic-administration.md) (topics, `broker config`, reassignments),
  [`topic produce`](/deep-dive-topic-produce.md) (transactions), [offsets and lag](/deep-dive-offsets-and-lag.md),
  [JVM diagnostics](/deep-dive-jvm-diagnostics.md) (thread dumps and flight recordings of a broker),
  [a slow or broken network](/deep-dive-network-traffic.md) (degrade a broker's network instead of stopping it)
- 📖 Confluent docs: [Kafka transactions](https://docs.confluent.io/platform/current/clients/transactions.html),
  [monitoring Kafka with JMX](https://docs.confluent.io/platform/current/kafka/monitoring.html)
- 🧠 CLI reference: [playground broker](/playground%20broker), [playground broker health](/playground%20broker%20health),
  [playground broker transactions](/playground%20broker%20transactions), [playground topic produce](/playground%20topic%20produce)
