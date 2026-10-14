# Fully Managed GCP Firestore Sink connector

## Objective

Quickly test the [Fully Managed GCP Firestore Sink](https://docs.confluent.io/cloud/current/connectors/cc-gcp-firestore-sink.html) connector.

The connector writes to a Firestore database (enterprise edition) through its MongoDB compatible endpoint.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

You need an active Google Cloud Platform (GCP) account with authorization to create resources.

| Variable | Description |
| --- | --- |
| `GCP_PROJECT` | GCP project id (required) |
| `GCP_KEYFILE_CONTENT` | Service account key content, only needed if `keyfile.json` is not present in this folder |
| `GCP_FIRESTORE_USER_CREDS` | Optional: name of the Firestore user credential to create (default `pg<user>fmfirestore`) |
| `GCP_FIRESTORE_CONNECTION_PASSWORD` | Optional: use this password instead of creating/rotating the Firestore user credential |
| `GCP_FIRESTORE_IAM_PROPAGATION_WAIT_SECONDS` | Optional: wait after granting the IAM role (default `60`) |

GCP credentials: place the service account key as `keyfile.json` in this folder, or export `GCP_KEYFILE_CONTENT`, generated with:

```bash
GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
```

Service account permissions:

* add the permissions listed [here](https://docs.cloud.google.com/firestore/mongodb-compatibility/docs/create-databases#permissions)
* add the `Project IAM Admin` role, needed to grant `roles/datastore.user` to the Firestore user

## How to run

```bash
playground run -f fully-managed-gcp-firestore-sink.sh
```

The script takes an optional positional argument: the GCP region (default `europe-west2`).

| Script | Description |
| --- | --- |
| `fully-managed-gcp-firestore-sink.sh` | Sinks Avro records to a Firestore collection |

## What the script does

1. Bootstraps the Confluent Cloud environment on GCP and recreates topic `products`.
2. Creates a Firestore database (enterprise edition, MongoDB compatible), retrieves its MongoDB endpoint, creates (or rotates) a Firestore user credential and grants it `roles/datastore.user`.
3. Produces 3 Avro records to `products`.
4. Creates the `FirestoreSink` fully managed connector writing to collection `kafka_products`.
5. Queries the collection with `mongosh` and checks that the `notebooks` record is present.
6. Asks before deleting the connector; on exit, revokes the IAM role and deletes the user credential and the database.
