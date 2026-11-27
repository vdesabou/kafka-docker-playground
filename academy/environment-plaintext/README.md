# Academy: exercises on the plaintext environment

Reproduction models of the broker, producer, Schema Registry and ksqlDB exercises of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy).
Each one starts the plaintext environment (3 brokers, KRaft, CP 8 or later, for 000017 to 000021) and plants one mistake of a
cluster, in its compose override or with the CLI:

| Model | Mistake | Exercise |
| --- | --- | --- |
| `broker-repro-000017-broker-never-joins-duplicate-node-id.sh` | `broker3` has the node id of `broker2` | [a broker never joins the cluster](https://kafka-docker-playground.io/#/academy?id=broker-a-broker-never-joins-the-cluster) |
| `broker-repro-000018-broker-rejected-inconsistent-cluster-id.sh` | `broker3` is formatted with another cluster id | [one broker is rejected by the controllers](https://kafka-docker-playground.io/#/academy?id=broker-one-broker-is-rejected-by-the-controllers) |
| `broker-repro-000019-not-leader-or-follower-copied-advertised-listeners.sh` | `broker3` advertises the address of `broker2` | [some records are lost, always for the same partitions](https://kafka-docker-playground.io/#/academy?id=broker-some-records-are-lost-always-for-the-same-partitions) |
| `broker-repro-000020-topic-creation-hangs-produce-works.sh` | 2 of the 3 controllers are down | [topic creation hangs, but produce works](https://kafka-docker-playground.io/#/academy?id=broker-topic-creation-hangs-but-produce-works) |
| `broker-repro-000021-acks-all-not-enough-replicas.sh` | a topic with 2 replicas and `min.insync.replicas=2`, one broker down | [acks=all fails after a broker crash](https://kafka-docker-playground.io/#/academy?id=producer-acksall-fails-after-a-broker-crash) |
| `broker-repro-000022-slow-producer-no-error-quota.sh` | a forgotten client quota of 50 KB/s (one broker is enough) | [slow, without any error](https://kafka-docker-playground.io/#/academy?id=producer-slow-without-any-error) |
| `broker-repro-000034-replica-slow-to-catch-up-rebalance-throttle-left.sh` | an Auto Data Balancer rebalance never followed by `status` or `finish`: its replication throttle stays (3 brokers) | [a restarted broker takes ages to catch up](https://kafka-docker-playground.io/#/academy?id=broker-a-restarted-broker-takes-ages-to-catch-up) |
| `broker-repro-000035-broker-refuses-migration-mode-zookeeper-to-kraft.sh` | phase 3 of a ZooKeeper to KRaft migration without `confluent.cluster.link.metadata.topic.enable` (CP 7.9.11, the compose override of `other/zookeeper-to-kraft-migration`) | [the broker refuses to start in migration mode](https://kafka-docker-playground.io/#/academy?id=zookeeper-to-kraft-migration-the-broker-refuses-to-start-in-migration-mode) |
| `broker-repro-000040-compacted-topic-keeps-old-versions.sh` | a compacted topic whose records all sit in the active segment (`segment.ms` 7 days by default): nothing is compacted (one broker is enough) | [the compacted topic keeps every old version](https://kafka-docker-playground.io/#/academy?id=broker-the-compacted-topic-keeps-every-old-version) |
| `schema-registry-repro-000026-producer-refused-incompatible-schema.sh` | a new required field without default, under the `BACKWARD` rule | [the new version of the producer is refused](https://kafka-docker-playground.io/#/academy?id=schema-registry-the-new-version-of-the-producer-is-refused) |
| `ksqldb-repro-000027-ksqldb-table-stays-empty.sh` | a `CREATE TABLE … AS SELECT` without `SET 'auto.offset.reset' = 'earliest'` | [the new table stays empty](https://kafka-docker-playground.io/#/academy?id=ksqldb-the-new-table-stays-empty) |

```bash
playground run -f academy/environment-plaintext/broker-repro-000017-broker-never-joins-duplicate-node-id.sh
```

The labs `other/deep-dive-labs/academy-broker.sh` (000017 to 000022, 000034, 000035 and 000040) and `academy-areas.sh` (000026 to 000029) replay them and their fixes every night.
