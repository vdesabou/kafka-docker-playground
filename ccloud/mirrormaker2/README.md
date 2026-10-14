# Using Mirror Maker 2 with Confluent Cloud

## Objective

Quickly test [MirrorMaker 2](https://cwiki.apache.org/confluence/display/KAFKA/KIP-382%3A+MirrorMaker+2.0) replicating from a local cluster (`A`) to Confluent Cloud (`B`), including consumer group offset synchronization.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Requires CP 5.4 or later (the script exits with code `111` otherwise).

## How to run

```bash
playground run -f mirrormaker2.sh
```

| Script | Description |
| --- | --- |
| `mirrormaker2.sh` | MirrorMaker 2 dedicated mode (`connect-mirror-maker`) from a local 3-broker cluster to Confluent Cloud |

## What the script does

1. Starts the `ccloud` environment with a local 3-broker cluster (`broker1`, `broker2`, `broker3`) and generates `connect-mirror-maker.properties` from `connect-mirror-maker-template.properties` with the Confluent Cloud credentials.
2. (Re)creates the `sales_A` topic in Confluent Cloud and deletes the MirrorMaker 2 internal topics of previous runs (no replication policy separator/alias: topic names are kept identical).
3. Starts `connect-mirror-maker` in the `connect` container (logs in `mirrormaker.log`), replicating `sales_A` with `sync.group.offsets.enabled = true`.
4. Produces 20 messages to `sales_A` on the local cluster, then consumes 10 of them with consumer group `my-consumer-group`.
5. Produces 20 more messages, waits for the offsets to be synced, then consumes `sales_A` in Confluent Cloud with `playground topic consume`: the group should resume from the previously committed offset.
