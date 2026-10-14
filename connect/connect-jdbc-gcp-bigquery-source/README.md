# JDBC GCP BigQuery Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with Google BigQuery, using the [Simba BigQuery JDBC driver](https://cloud.google.com/bigquery/docs/reference/odbc-jdbc-drivers) (1.3.2.1003).

## Prerequisites

* An active Google Cloud Platform (GCP) account with authorization to create resources.
* With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

| Variable | Description |
| --- | --- |
| `GCP_PROJECT` | GCP project ID (required) |
| `GCP_KEYFILE_CONTENT` | Service account key content, only if `keyfile.json` is not present in this folder (see below) |
| `SERVICE_ACCOUNT_EMAIL` | Optional: service account email injected into `OAuthServiceAcctEmail` of the JDBC URL (default: `client_email` of `keyfile.json`) |

### GCP BigQuery setup

* Follow [Quickstart using the web UI in the GCP Console](https://cloud.google.com/bigquery/docs/quickstarts/quickstart-web-ui) to get familiar with GCP BigQuery.
* Create a service account from the IAM & Admin console.

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `BigQuery` > `BigQuery Admin`:

![Service Account setup](Screenshot2.png)

Create a key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json` and place it in this folder, or set `GCP_KEYFILE_CONTENT`:

```bash
export GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
```

## How to run

```bash
export GCP_PROJECT="<project id>"
playground run -f jdbc-gcp-bigquery-source.sh
```

| Script | Description |
| --- | --- |
| `jdbc-gcp-bigquery-source.sh` | JDBC source in `bulk` mode on a BigQuery table |

## What the script does

1. Downloads the Simba BigQuery JDBC driver if needed and copies its jars into the JDBC connector `lib` folder (with CP 8+, only the jars not already on the worker classpath, to avoid gRPC / google-auth class conflicts).
2. Authenticates `gcloud` with the service account key, then (re)creates a dataset unique to your environment and a `customers` table with one row, using `bq`.
3. Creates the `jdbc-gcp-bigquery-source` connector (`mode=bulk`, `catalog.pattern=$GCP_PROJECT`, `schema.pattern=<dataset>`, `topic.prefix=gcp-`), mounting the key file at `/tmp/keyfile.json`.
4. Verifies that records land in topic `gcp-customers` with `playground topic consume`.

## Known issues

`mode=timestamp` (with `timestamp.column.name=updated_at`) fails because the generated query uses the fully qualified table name `` `project`.`dataset`.`customers`.`updated_at` ``, which BigQuery rejects with `Unrecognized name: <project>`. The script uses `mode=bulk` for that reason.

Driver documentation: [Simba Google BigQuery JDBC Connector Install and Configuration Guide](https://cloud.google.com/bigquery/docs/reference/odbc-jdbc-drivers).
