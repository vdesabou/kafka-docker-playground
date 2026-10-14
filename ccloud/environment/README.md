# Confluent Cloud

## Description

This is the `ccloud` environment: a local deployment bootstrapped to Confluent Cloud (Kafka cluster and Schema Registry in Confluent Cloud):

* 1 Connect worker (`connect`, REST API on port 8083)
* optional, enabled with the corresponding playground flags (profiles):
  * Control Center (`control-center` profile, port 9021)
  * Conduktor (`conduktor` profile, port 8080)
  * Prometheus and Grafana (`grafana` profile, ports 9090 and 3000)

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

The environment is started by examples with:

```bash
playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.yml"
```

`start.sh` takes an optional docker-compose override file as first argument.

## What the script does

1. Bootstraps the Confluent Cloud environment (environment, cluster, Schema Registry and API keys) and generates the `data` file (from `data.template`) used to externalize secrets in connector configurations with `${file:/datacloud:<key>}`.
2. Recreates the `_confluent-monitoring` topic and deletes the Connect worker internal topics `connect-status-<TAG>`, `connect-offsets-<TAG>` and `connect-configs-<TAG>`.
3. Starts the containers with `docker compose` (plus the override file and the enabled profiles; Replicator monitoring is disabled for CP versions older than 5.5).
4. Stores the docker compose command in `playground.ini` so that `playground container recreate` works, and waits for the Connect worker to be ready.
