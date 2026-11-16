# cp-ansible day-2 operations

## Objective

Changes on a **running** cluster deployed by cp-ansible, replayed step by step while a workload runs through them: what
the clients see at each step, what the classic mistake looks like, and a check at the end that no record was lost.
They follow the procedures cp-ansible documents (change the inventory, run `confluent.platform.all` with
`deployment_strategy=rolling`), with the [`playground ansible`](https://kafka-docker-playground.io/#/deep-dive-ansible)
commands, on the [ansible environment](../../environment/ansible/).

The workload (`day2-utils.bash`):

- `kafka-verifiable-producer` on the connect host, 20 records/s, `acks=all`, **no retries**: every leader move, every
  broker it cannot reach is a send error, so the disruption of each step is visible
- the FileStream sink connector, writing the topic to a file on the worker
- at the end: every acked record is in the topic and in the file of the sink

| Example | Change | The classic mistake it shows |
| --- | --- | --- |
| `rolling-upgrade.sh` | CP 8.3.2 → the default CP version (or `--tag`), 3 brokers | the feature level is not finalized by cp-ansible; a change applied with the default `deployment_strategy` (`parallel`) restarts every broker at once |
| `enable-sasl-ssl.sh` | PLAINTEXT → SASL_SSL in 3 steps: a SASL_SSL listener next to PLAINTEXT, the clients moved, PLAINTEXT closed | a client left on PLAINTEXT: it stops producing, with `Bootstrap broker broker:9092 … disconnected` in a loop, or `java.lang.OutOfMemoryError` in its network thread |

Each example starts its own ansible environment and takes 15 to 25 minutes.

## How to run

```bash
playground run -f other/cp-ansible-day2/rolling-upgrade.sh
playground run -f other/cp-ansible-day2/enable-sasl-ssl.sh
```

`rolling-upgrade.sh` goes from 8.3.2 (`DAY2_OLD_VERSION`) to the CP version of the run: `--tag` for another target.

The same commands work by hand on any ansible environment, including a customer inventory
(`--ansible-inventory`): `playground ansible inventory set`, `playground ansible playbook --rolling`,
`playground ansible upgrade --to <version>`.

## What you see

Recorded locally (Docker Desktop, arm64), CP 8.4.1 and cp-ansible 8.4.0.

### `rolling-upgrade.sh` (16 min 39 s)

| Step | Brokers restarted | Send errors | Longest time without an ack |
| --- | --- | --- | --- |
| rolling upgrade 8.3.2 → 8.4.1 (`playground ansible upgrade --to 8.4.1`) | 10:52:56, 10:53:38, 10:54:22 | 2 | 0.1 s |
| a broker property, `playground ansible playbook --limit kafka_broker` (**parallel**, the default of cp-ansible) | 10:57:09, 10:57:09, 10:57:09 | **259** | **13.0 s** |
| the same, `--rolling` | 10:58:29, 10:59:09, 10:59:50 | 1 | 0.1 s |

```text
Feature: confluent.metadata.version  SupportedMinVersion: CP-7.3-IV3  SupportedMaxVersion: CP-8.4-IV2A  FinalizedVersionLevel: CP-8.3-IV0B   <- after the upgrade
⬆️ kafka-features upgrade --feature confluent.metadata.version=141
Feature: confluent.metadata.version  SupportedMinVersion: CP-7.3-IV3  SupportedMaxVersion: CP-8.4-IV2A  FinalizedVersionLevel: CP-8.4-IV2A
🔎 acked by the producer: 12886, records in topic day2: 12886, lines written by the sink connector: 12886
✅ no record lost: every acked record is in the topic and was written by the sink connector
```

The brokers of the example hold little data and are back in seconds: with real data a broker takes minutes to start,
and every partition is offline meanwhile. The number of send errors of a parallel restart varies from run to run (the
producer waits for metadata while no broker answers), the restart times don't: the example checks them.

### `enable-sasl-ssl.sh` (17 min 59 s)

```text
listeners=INTERNAL://:9092,BROKER://:9091                                                               <- step 1
listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,BROKER:PLAINTEXT
listeners=INTERNAL://:9092,BROKER://:9091,CLIENT://:9093                                                <- step 2, a SASL_SSL listener
listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,BROKER:PLAINTEXT,CLIENT:SASL_SSL
bootstrap.servers=broker:9093,broker2:9093,broker3:9093                                                 <- step 3, connect moved
security.protocol=SASL_SSL
listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:SASL_SSL,BROKER:PLAINTEXT,CLIENT:SASL_SSL  <- step 4, PLAINTEXT closed
📊 after closing PLAINTEXT (producer): 14347 records acked, 6 send errors
💥 the forgotten client: acks in the last 20 seconds: 0, what it logs once PLAINTEXT is closed:
WARN [Producer clientId=producer-1] Bootstrap broker broker:9092 (id: -1 rack: null isFenced: false) disconnected (org.apache.kafka.clients.NetworkClient)
🔎 acked by the producer: 27542, records in topic day2: 27543, lines written by the sink connector: 27543
✅ no record lost: every acked record is in the topic and was written by the sink connector
```

The forgotten client either loops on `Bootstrap broker … disconnected`, or dies with
`java.lang.OutOfMemoryError: Java heap space` in `NetworkReceive.readFrom` (seen in another run): a PLAINTEXT client
reads the first bytes of the TLS handshake as the size of a response (KAFKA-4090), the symptom customers report as "our
producers run out of memory after we enabled TLS". The inter-broker listener (`BROKER`, 9091) is left as it is: changing
it in a single rolling run breaks the replication between the brokers already restarted and the others.

Good to know: cp-ansible writes the broker's `client.properties` with the security of the **inter-broker** listener, not
of `INTERNAL`: the playground commands pair it with that listener's port (9091 here).

