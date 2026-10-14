# Centralized license for self-managed connectors (using Confluent Cloud)

## Objective

Quickly test [centralized license](https://docs.confluent.io/platform/current/connect/license.html) configuration for self-managed connectors running on a local Connect worker connected to Confluent Cloud.

The license is configured once at the worker level (`CONNECT_CONFLUENT_LICENSE` and `CONNECT_CONFLUENT_TOPIC_*` environment variables in the docker-compose override files), so the connector configurations do not contain any `confluent.license` / `confluent.topic.*` properties. The `confluent.topic.*` worker settings point to the Confluent Cloud cluster.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Used by | Description |
| --- | --- | --- |
| `SERVICENOW_URL` | `servicenow-source.sh` | ServiceNow instance URL, ending with `/` (e.g. `https://dev12345.service-now.com/`) |
| `SERVICENOW_PASSWORD` | `servicenow-source.sh` | Password of the ServiceNow `admin` user |

AWS credentials (`redshift.sh`): export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.

## How to run

```bash
playground run -f mqtt-source.sh
```

| Script | Description |
| --- | --- |
| `mqtt-source.sh` | MQTT Source connector with a local Mosquitto broker |
| `redshift.sh` | AWS Redshift Sink connector, creating an AWS Redshift cluster |
| `servicenow-source.sh` | ServiceNow Source connector on table `incident` |
| `replicator-onprem-to-cloud.sh` | Replicator from a local on-premise cluster (ZooKeeper + broker) to Confluent Cloud |

## What the script does

1. Deletes the `_confluent-command` license topic in Confluent Cloud, so the license is created again.
2. Starts the `ccloud` environment with the variant docker-compose override, which sets the centralized license on the Connect worker (plus Mosquitto for MQTT, a local ZooKeeper and broker for Replicator).
3. Creates the external resources if needed: for `redshift.sh`, a single-node AWS Redshift cluster and a security group allowing port 5439 (previous ones are deleted first).
4. Creates the connector without any license property.
5. Produces test data: an MQTT message with `mosquitto_pub`, 3 Avro records to `orders` with `playground topic produce`, one ServiceNow incident through the ServiceNow REST API, or 10 records to `products` on the on-premise cluster.
6. Verifies the result with `playground topic consume` (MQTT, ServiceNow, Replicator) or by querying the `orders` table in Redshift with `psql`.
