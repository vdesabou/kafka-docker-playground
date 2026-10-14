# GO client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [GO example](https://github.com/confluentinc/examples/tree/5.4.1-post/clients/cloud/go) client using Confluent Cloud.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Go producer and consumer running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `librdkafka.config` from `librdkafka.config.template` with the cluster bootstrap servers and API key.
2. Recreates topic `client_go_<TAG>` with `playground topic delete` / `playground topic create`.
3. Builds the `vdesabou/go-ccloud-example-docker` image.
4. Runs the producer container `go-ccloud-producer`.
5. Runs the consumer container `go-ccloud-consumer` in the background, with logs in `/tmp/result.log`, and checks that the consumed records contain `alice`.
