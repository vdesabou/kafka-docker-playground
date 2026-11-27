# Academy: broker exercises

Reproduction models of the broker exercises of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy).
Each one starts the plaintext environment (3 brokers, KRaft, CP 8 or later, except 000022) and plants one mistake of a
cluster, in its compose override or with the CLI:

| Model | Mistake | Exercise |
| --- | --- | --- |
| `broker-repro-000017-broker-never-joins-duplicate-node-id.sh` | `broker3` has the node id of `broker2` | [a broker never joins the cluster](https://kafka-docker-playground.io/#/academy?id=broker-a-broker-never-joins-the-cluster) |
| `broker-repro-000018-broker-rejected-inconsistent-cluster-id.sh` | `broker3` is formatted with another cluster id | [one broker is rejected by the controllers](https://kafka-docker-playground.io/#/academy?id=broker-one-broker-is-rejected-by-the-controllers) |
| `broker-repro-000019-not-leader-or-follower-copied-advertised-listeners.sh` | `broker3` advertises the address of `broker2` | [some records are lost, always for the same partitions](https://kafka-docker-playground.io/#/academy?id=broker-some-records-are-lost-always-for-the-same-partitions) |
| `broker-repro-000020-topic-creation-hangs-produce-works.sh` | 2 of the 3 controllers are down | [topic creation hangs, but produce works](https://kafka-docker-playground.io/#/academy?id=broker-topic-creation-hangs-but-produce-works) |
| `broker-repro-000021-acks-all-not-enough-replicas.sh` | a topic with 2 replicas and `min.insync.replicas=2`, one broker down | [acks=all fails after a broker crash](https://kafka-docker-playground.io/#/academy?id=producer-acksall-fails-after-a-broker-crash) |
| `broker-repro-000022-slow-producer-no-error-quota.sh` | a forgotten client quota of 50 KB/s (one broker is enough) | [slow, without any error](https://kafka-docker-playground.io/#/academy?id=producer-slow-without-any-error) |

```bash
playground run -f academy/environment-plaintext/broker-repro-000017-broker-never-joins-duplicate-node-id.sh
```

The lab `other/deep-dive-labs/academy-broker.sh` replays them and their fixes every night.
