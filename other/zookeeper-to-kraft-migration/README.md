# ZooKeeper to KRaft migration (self-managed, CP 7.9)

## Objective

Migrate a self-managed Confluent Platform cluster from ZooKeeper to KRaft, with the phases of the
[Confluent documentation](https://docs.confluent.io/platform/7.9/installation/migrate-zk-kraft.html), and check that no
record is lost: the same steps as the "How a ZooKeeper cluster moves to KRaft" visual of GTS, on a running cluster.

For the CFK version (a `KRaftMigrationJob`), see [other/cfk-day2](../cfk-day2/README.md).

## What the example does

ZooKeeper is removed in CP 8: with a CP 8 tag (the default) the example runs on **CP 7.9.11**. Another 7.6 to 7.9 version
works with `--tag` (the `inter.broker.protocol.version` of the migration follows: 7.9 is 3.9).

| Phase | What the example does | What to look for |
| --- | --- | --- |
| start | ZooKeeper, one broker in ZooKeeper mode, 5 records; the KRaft controller container waits for the cluster id | |
| 1 | reads the cluster id of the ZooKeeper cluster: `zookeeper-shell localhost:2181 get /cluster/id` | `{"version":"1","id":"…"}` |
| 2 | gives it to the controller (`migration/cluster.id`): the image formats its storage with it (`CLUSTER_ID`) and starts it with `zookeeper.metadata.migration.enable=true` and `zookeeper.connect` | `No brokers are known to KRaft, waiting for brokers to register` |
| 3 | restarts the broker with `zookeeper.metadata.migration.enable=true`, `controller.quorum.voters`, `controller.listener.names`, the `CONTROLLER` listener in the protocol map, `inter.broker.protocol.version=3.9` and `confluent.cluster.link.metadata.topic.enable=true`; 5 records in dual-write | `Completed migration of metadata from ZooKeeper to KRaft. 127 records were generated…` in the controller |
| 4 | restarts the broker in KRaft mode: `process.roles=broker`, `node.id` = its `broker.id`, migration off, no `zookeeper.connect` | `[KafkaRaftServer nodeId=1] Kafka Server started` |
| 5 | restarts the controller with migration off and no `zookeeper.connect` | `[KafkaRaftServer nodeId=3000] Kafka Server started` |
| 6 | stops ZooKeeper, 5 records | |
| check | the 15 records of the three phases are in the topic; `playground broker describe` shows the KRaft quorum | `Observers (brokers): 1` |

Each restart is a `playground container set-environment-variables`: the variables of a phase are kept for the next
ones (on the same container or another one).

Gotchas the example shows:

* **Confluent Server** refuses to start in migration mode without `confluent.cluster.link.metadata.topic.enable=true`:
  `java.lang.IllegalArgumentException: requirement failed: Must have link coordinator enabled during migration.`
  (`playground analyze logs`: 🚚 ZooKeeper to KRaft migration: link coordinator not enabled).
* The controller must be formatted with the **cluster id of ZooKeeper** (`/cluster/id`), not a new one.
* The controller needs the **inter-broker listener** of the brokers (`inter.broker.listener.name` and its protocol): during
  the migration it sends the metadata to the ZooKeeper brokers.
* Until phase 4, a rollback to ZooKeeper is possible (the controller writes every change to ZooKeeper, dual-write). After
  the brokers run in KRaft mode, there is no way back.

## How to run

```bash
playground run -f other/zookeeper-to-kraft-migration/zookeeper-to-kraft-migration.sh
```
