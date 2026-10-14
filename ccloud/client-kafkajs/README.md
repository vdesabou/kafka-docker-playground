# KafkaJS client (producer and consumer) (using Confluent Cloud)

## Objective

Quickly test the [KafkaJS](https://kafka.js.org) client using Confluent Cloud.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | KafkaJS producer and consumer running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `producer.js` and `consumer.js` from their templates with the cluster bootstrap servers and API key.
2. Recreates topic `client_kafkajs_<TAG>` with `playground topic delete` / `playground topic create`.
3. Builds the `vdesabou/kafkajs-ccloud-example-docker` image.
4. Runs the producer container `kafkajs-ccloud-producer` in the background.
5. Runs the consumer container `kafkajs-ccloud-consumer` in the background, with logs in `/tmp/result.log`, and checks that the consumed records contain `value-`.
