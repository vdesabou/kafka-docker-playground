# Fully Managed Marketo Sink connector



## Objective

Quickly test [Fully Managed Marketo Sink](https://docs.confluent.io/cloud/current/connectors/cc-marketo-sink.html) connector.

The script:

* produces 3 JSON records with operation `upsert_lead` to topic `marketo-leads`, for example:

```json
{"operation": "upsert_lead", "data": {"lookupField": "email", "email": "playground-...-1@example.com", "firstName": "John", "lastName": "Doe1"}}
```

* creates the connector with `marketo.operation` `upsert_lead`
* verifies with the Marketo REST API that the 3 leads exist
* deletes the leads at the end of the run

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

Marketo setup is the same as for the [Marketo Source](../../connect/connect-marketo-source/README.md) example: create an API-only user and a custom LaunchPoint service (Admin > Integration > LaunchPoint) to get the client id and secret.

The Munchkin ID is extracted from `MARKETO_ENDPOINT_URL`.

```bash
export MARKETO_ENDPOINT_URL="https://<munchkin-id>.mktorest.com"
export MARKETO_CLIENT_ID="<client-id>"
export MARKETO_CLIENT_SECRET="<client-secret>"
```

## How to run

```
$ just use <playground run> command and search for fully-managed-marketo-sink.sh in this folder
```
