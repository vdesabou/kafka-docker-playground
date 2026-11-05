# Kafka Streams stateful application

## Objective

A base to reproduce [Kafka Streams](https://docs.confluent.io/platform/current/streams/overview.html) support cases:
a stateful application (repartition topic, state store, changelog topic) running as 3 instances, configured by a
`streams.properties` file (drop the customer's `StreamsConfig` in), built with the Kafka Streams version of the
customer.

The application logs what matters in a Streams case: its state transitions (`CREATED`, `REBALANCING`, `RUNNING`,
`ERROR`…), the active and standby tasks of each thread when it becomes `RUNNING`, and the restoration of its state
store (`♻️ Restore started` / `✅ Restore completed`, with the number of records restored).

## How to run

```bash
playground run -f kafka-streams-count<tab>
```

With the Kafka Streams version of the customer (any Apache Kafka version since 3.0.0, patch included), which does not
have to match the brokers:

```bash
playground run -f kafka-streams-count<tab> --tag 8.2.0 --client-version 3.7.1
```

The application is built when the version changes (`streams/target/kafka-streams-count-<version>-jar-with-dependencies.jar`,
`mvn clean package`: only the jar of the last version is kept). An older version is skipped (`exit 111`).

## What the script does

1. builds the application with `kafka-streams` `$KAFKA_CLIENT_TAG` (`--client-version`, or `CLIENT_VERSION` exported;
   by default the version matching the CP version, for example 4.2.0 with CP 8.2)
2. starts the plaintext environment and 3 instances of the application, `streams`, `streams2` and `streams3`
   (application id `streams-count`), each reading `streams.properties`. The topology:

   ```text
   streams-input (6 partitions)
     → groupBy(value → "bucket-<hash % 10>")   repartition topic streams-count-by-bucket-repartition
     → count()                                  state store counts-store, changelog streams-count-counts-store-changelog
     → streams-output                           running count per bucket
   ```

3. waits for the 3 instances to be `RUNNING`, produces 1000 records to `streams-input`, and checks that the latest
   count of each bucket in `streams-output` adds up to 1000
4. shows the members of the consumer group `streams-count` and their partitions: `playground consumer-group describe
   --group streams-count --members`
5. kills `streams2` (`playground container kill`): after the session timeout, its tasks move to `streams` and
   `streams3`, which restore the state store from the changelog topic. Produces 1000 more records, the counts add up
   to 2000
6. restarts `streams2`. With the high availability task assignor (Kafka Streams 2.6+), it first gets standby
   (warm-up) tasks only, then its active tasks back after a follow-up rebalance, and restores their state from the
   changelog topic before processing:

   ```text
   📋 Assignment of streams-count-…-StreamThread-1: active tasks [], standby tasks [1_1, 1_4]
   ♻️ Restore started for store counts-store from streams-count-counts-store-changelog-1: offsets 0 to 6
   ✅ Restore completed for store counts-store from streams-count-counts-store-changelog-1: 6 records restored
   📋 Assignment of streams-count-…-StreamThread-1: active tasks [0_1, 0_4, 1_1, 1_4], standby tasks []
   ```

   Produces 1000 more records, the counts add up to 3000

The restore checks only count the log lines written after the kill and after the restart (`playground container logs
--since`): container logs survive a restart.

## Use it in a repro

```bash
# what each instance is doing
playground container logs --container streams2 --grep "state transition\|Assignment of\|Restore"

# replace the StreamsConfig (num.standby.replicas, processing.guarantee=exactly_once_v2, …), then restart the instances
playground container restart --container streams --container streams2 --container streams3

# rebalance, failure and network scenarios
playground container kill --container streams3
playground broker rolling-restart
playground debug degrade-traffic --container streams --latency 500ms --action start

# committed offsets and lag of the application
playground consumer-group describe --group streams-count
```

`streams.properties` is mounted in the instances: change it, then restart them. `bootstrap.servers` comes from the
`STREAMS_BOOTSTRAP_SERVERS` variable of the compose file. Client security settings can go in an
`/etc/kafka-streams/extra.properties` file (read when it exists): for now the example only runs on the plaintext
environment.
