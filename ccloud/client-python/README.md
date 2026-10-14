# Python client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Python example](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/python.html#run-all-the-code-in-docker) client using Confluent Cloud.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Python producer and consumer running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `librdkafka.config` from `librdkafka.config.template` with the cluster bootstrap servers, API key and Schema Registry credentials.
2. Recreates topics `client_python_<TAG>` and `client_python_avro_<TAG>` with `playground topic delete` / `playground topic create`.
3. Builds the `vdesabou/python-ccloud-example-docker` image.
4. Runs `producer.py` then `consumer.py` on `client_python_<TAG>`, with consumer logs in `/tmp/result.log`, and checks that the consumed records contain `alice`.
5. Runs `producer.py` then `consumer.py` again on `client_python_avro_<TAG>` with the same check.

Note: the second run (logged as "AVRO") uses the same `producer.py` / `consumer.py`; the Schema Registry variants `producer_ccsr.py` / `consumer_ccsr.py` are present in the folder but not used by `start.sh`.
