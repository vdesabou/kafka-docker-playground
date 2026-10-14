# Mapr Sink connector

## Objective

Quickly test the [MapR DB Sink](https://docs.confluent.io/kafka-connectors/maprdb/current/overview.html) connector.

## Prerequisites

This example only runs with CP 7.x (the script exits with code 111 with CP < 7.0.0 or CP >= 8.0.0, as the connector is deprecated).

| Variable | Description |
| --- | --- |
| `HPE_MAPR_EMAIL` | Email of your HPE account, used to download the MapR client from `https://package.ezmeral.hpe.com/releases/` |
| `HPE_MAPR_TOKEN` | Token of your HPE account |

To get them:

1. You need an [HPE Account](https://docs.ezmeral.hpe.com/datafabric-customer-managed/74/AdvancedInstallation/Obtaining_an_HPE_Account.html). ❗ Make sure to set an Organization and use a work email address, otherwise you won't have access to https://package.ezmeral.hpe.com/releases/
2. [Obtain a token](https://docs.ezmeral.hpe.com/datafabric-customer-managed/74/AdvancedInstallation/Obtaining_a_Token.html) for your HPE account.

## How to run

```bash
export HPE_MAPR_EMAIL="<your HPE account email>"
export HPE_MAPR_TOKEN="<your HPE token>"
playground run -f mapr-sink.sh
```

The MapR Control System (MCS) UI is running at [https://127.0.0.1:8443](https://127.0.0.1:8443) (`mapr`/`mapr`).

## What the script does

1. Generates `maprtech.repo` from `maprtech.repo.template` with your HPE credentials and starts the environment with a MapR sandbox container (`docker-compose-kraft.yml` is used when KRaft is enabled).
2. Installs and configures the MapR client (secure mode) in the `connect` container.
3. Creates MapR DB table `/mapr/maprdemo.mapr.io/maprtopic`.
4. Produces 3 JSON records (with schema) to topic `maprtopic` with `playground topic produce`.
5. Creates the MapR DB sink connector `mapr-sink` (`mapr.table.map.maprtopic=/mapr/maprdemo.mapr.io/maprtopic`).
6. Verifies with `mapr dbshell` that records `record1`, `record2` and `record3` are in the table.
