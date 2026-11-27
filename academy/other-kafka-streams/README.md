# Academy: Kafka Streams exercises

Reproduction models of the Kafka Streams exercises of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy).
They run the Kafka Streams application of [other/kafka-streams](../../other/kafka-streams/README.md) (3 instances, built
with the Kafka Streams version of `--client-version`) and plant one problem:

| Model | Problem | Exercise |
| --- | --- | --- |
| `streams-repro-000036-one-application-stops-on-poison-pill.sh` | a record of `payments` that is not Avro: `streams-serde-errors-fail-on-poison-pill` (default `LogAndFailExceptionHandler`) stops, `streams-serde-errors` (`LogAndContinueExceptionHandler`) skips it | [one application stopped on a bad record](https://kafka-docker-playground.io/#/academy?id=kafka-streams-one-application-stopped-on-a-bad-record-the-other-one-keeps-going) |
| `streams-repro-000038-join-loses-orders-topics-not-co-partitioned.sh` | `orders-by-customer` (6 partitions) joined with `customers` (3) without repartition: since Kafka Streams 3.2 nothing refuses it, the orders of c1 and c3 are lost | [the enriched orders of most customers never come out](https://kafka-docker-playground.io/#/academy?id=kafka-streams-the-enriched-orders-of-most-customers-never-come-out) |

```bash
playground run -f academy/other-kafka-streams/streams-repro-000036-one-application-stops-on-poison-pill.sh
```

The lab `other/deep-dive-labs/academy-areas.sh` replays them and their fixes every night.
