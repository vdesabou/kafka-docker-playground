# Auto Data Balancer (confluent-rebalancer)

## Objective

Rebalance the partitions of a topic onto a broker added to the cluster, with the Auto Data Balancer tool of Confluent
Server ([documentation](https://docs.confluent.io/platform/current/clusters/rebalancer/index.html)): the plan, the moves
under a replication throttle, the status until they are done, and `finish` to remove the throttle.

Auto Data Balancer is the command line tool that comes before Self-Balancing Clusters: a rebalance runs only when an
operator starts it, and its throttle stays until `status` or `finish` sees the moves completed. Customers still run it,
and its steps are the ones of the "How an Auto Data Balancer rebalance flows" visual of GTS.

## What the example does

On the plaintext environment with 3 brokers (CP 8, KRaft):

1. Topic `orders`, 6 partitions with 2 replicas, all on brokers 1 and 2 (`playground topic reassign --replicas 1,2`),
   as on a cluster that grew from 2 to 3 brokers. 30 MB of records.
2. Waits for the Confluent Metrics Reporter (enabled with Confluent Server images) to publish the sizes of the partitions
   in `_confluent-metrics`, which the rebalancer reads.
3. `confluent-rebalancer execute --topics orders --throttle 1000000 --force --verbose`: the plan per broker (leaders,
   replicas, size before -> after), then the reassignment starts.

   ```
   You are about to move 4 replica(s) for 4 partitions to 1 broker(s) with total size 21.1 MB.
   Broker stats (before -> after):
   	Broker     Leader Count    Replica Count   Size (MB)            Free Space (%)
   	1          6 -> 2          6 -> 4          30.1 -> 19.6         78.2 -> 78.2
   	2          0 -> 2          6 -> 4          30.1 -> 19.5         78.2 -> 78.2
   	3          0 -> 2          0 -> 4          0 -> 21.1            78.2 -> 78.2
   ```

4. `confluent-rebalancer status` until `No rebalance is currently in progress`, then `confluent-rebalancer finish`:
   `The rebalance has completed and throttling has been disabled`.
5. `playground topic elect-leader`: the rebalancer changes the preferred leaders, the leaders themselves only move at the
   next preferred leader election (`auto.leader.rebalance.enable`, every `leader.imbalance.check.interval.seconds`).
6. Checks that broker 3 has replicas of `orders` and leads some of them.

Good to know:

* The throttle (`leader.replication.throttled.rate`, `follower.replication.throttled.rate` and the throttled replicas
  of the topics) is only removed by a `status` or `finish` run after the moves complete: a rebalance started and never
  followed keeps replication throttled.
* `--remove-broker-ids <ids>` moves every replica away from brokers to decommission them.
* Self-Balancing Clusters (`confluent.balancer.enable=true`) and Auto Data Balancer must not run on the same cluster.

## How to run

```bash
playground run -f other/auto-data-balancer/auto-data-balancer.sh
```
