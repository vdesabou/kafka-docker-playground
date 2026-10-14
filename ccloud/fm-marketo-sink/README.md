# Fully Managed Marketo Sink connector

## Objective

Quickly test the [Fully Managed Marketo Sink](https://docs.confluent.io/cloud/current/connectors/cc-marketo-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Marketo setup is the same as for the [Marketo Source](../../connect/connect-marketo-source/README.md) example: create an API-only user and a custom LaunchPoint service (Admin > Integration > LaunchPoint) to get the client id and secret.

| Variable | Description |
| --- | --- |
| `MARKETO_ENDPOINT_URL` | Marketo REST endpoint, e.g. `https://<munchkin-id>.mktorest.com` (the Munchkin ID is extracted from it) |
| `MARKETO_CLIENT_ID` | LaunchPoint service client id |
| `MARKETO_CLIENT_SECRET` | LaunchPoint service client secret |

They can also be passed as positional arguments, in this order.

## How to run

```bash
export MARKETO_ENDPOINT_URL="https://<munchkin-id>.mktorest.com"
export MARKETO_CLIENT_ID="<client-id>"
export MARKETO_CLIENT_SECRET="<client-secret>"
playground run -f fully-managed-marketo-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-marketo-sink.sh` | Upserts 3 leads in Marketo (`marketo.operation` `upsert_lead`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `marketo-leads`.
2. Produces 3 JSON records with operation `upsert_lead`, for example:

   ```json
   {"operation": "upsert_lead", "data": {"lookupField": "email", "email": "playground-...-1@example.com", "firstName": "John", "lastName": "Doe1"}}
   ```

3. Creates the `MarketoSink` fully managed connector with `marketo.operation` `upsert_lead`.
4. Verifies with the Marketo REST API that the 3 leads exist (up to 5 minutes).
5. Asks before deleting the connector; on exit, deletes the created leads.
