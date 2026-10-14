# HTTP Source V2 connector

## Objective

Quickly test the [HTTP Source V2](https://docs.confluent.io/cloud/current/connectors/cc-http-source-v2.html) fully managed connector, running as a self-managed connector.

## Prerequisites

Confluent employees only: the scripts use the fully managed connector zip `confluentinc-kafka-connect-http-v2-0.1.0-rc-acd8307-cloud.zip`, fetched with `get_3rdparty_file` (the script exits with an error if it cannot be retrieved). To use another build, export `CONNECTOR_ZIP` with the absolute path of the zip, or pass `--connector-zip`.

## How to run

```bash
playground run -f http-v2-source-simple-incrementing.sh
```

| Script | Description |
| --- | --- |
| `http-v2-source-simple-incrementing.sh` | `SIMPLE_INCREMENTING` offset mode against a mocked Atlassian Confluence `/wiki/rest/api/space` API (`start=${offset}&limit=1`) |
| `http-v2-source-cursor-pagination.sh` | `CURSOR_PAGINATION` offset mode against a mocked GCS list objects API (`nextPageToken`) |
| `http-v2-source-chaining-offset.sh` | `CHAINING` offset mode with a POST body using Elasticsearch `search_after` pagination |
| `http-v2-source-no-auth.sh` | `SIMPLE_INCREMENTING` mode, no authentication, against the simple `httpserver` with a fixed response body |
| `http-v2-source-oauth2.sh` | `SIMPLE_INCREMENTING` mode with OAuth2 client credentials against [kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo) |

## What the script does

1. Retrieves the connector zip, downloads `jcl-over-slf4j-2.0.7.jar` and copies it into the connector `lib` folder.
2. Starts the environment with the HTTP server matching the variant.
3. Sets `org.apache.http` log level to `TRACE`.
4. Creates the `http-source` connector (`io.confluent.connect.http.source.GenericHttpSourceConnector`, one API `api1`) writing to `http-source-topic-v2` (`http-topic-spaces` for the simple incrementing variant).
5. For the no-auth and OAuth2 variants, PUTs a JSON message to the HTTP server (with a bearer token for OAuth2).
6. Verifies records with `playground topic consume` (15 records for the paginated variants, 3 for chaining, 1 otherwise).
