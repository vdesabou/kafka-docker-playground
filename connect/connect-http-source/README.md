# HTTP Source connector

## Objective

Quickly test the [HTTP Source](https://docs.confluent.io/kafka-connectors/http-source/current/overview.html) connector (self-managed version).

The HTTP endpoint is either [vdesabou/kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo) (proxy and OAuth2 variants) or the Node.js `httpserver` from `connect/connect-http-sink/httpserver`, which mocks paginated APIs (Confluence, GCS, Elasticsearch).

## Prerequisites

With CP 8.0+, connector version 0.2.0 or later is required (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f http-source-simple-incrementing.sh
```

| Script | Description |
| --- | --- |
| `http-source-simple-incrementing.sh` | `SIMPLE_INCREMENTING` offset mode against a mocked Atlassian Confluence `/wiki/rest/api/space` API (`start=${offset}&limit=1`) |
| `http-source-cursor-pagination.sh` | `CURSOR_PAGINATION` offset mode against a mocked GCS list objects API (`nextPageToken`) |
| `http-source-chaining-offset.sh` | `CHAINING` offset mode with a POST body using Elasticsearch `search_after` pagination |
| `http-source-no-auth-proxy.sh` | `SIMPLE_INCREMENTING` mode, no authentication, through an nginx forward proxy |
| `http-source-oauth2.sh` | `SIMPLE_INCREMENTING` mode with OAuth2 client credentials |

## What the script does

1. Downloads `jcl-over-slf4j-2.0.7.jar` and copies it into the HTTP Source connector `lib` folder.
2. Starts the environment with the HTTP server (and `nginx-proxy` for the proxy variant).
3. Sets `org.apache.http` log level to `TRACE` (pagination variants).
4. Creates the `http-source` connector writing to `http-topic-${entityName}` (`http-topic-messages` or `http-topic-spaces`).
5. For the proxy and OAuth2 variants, PUTs a JSON message to the demo service (with a bearer token for OAuth2).
6. Verifies records with `playground topic consume` (15 records for the pagination variants, 1 otherwise).

## Notes

- Chaining offset mode: if `size` in the request body is too small, data loss can occur when more documents than `size` share the same sort value.
- Related fully managed docs: [cursor pagination](https://docs.confluent.io/cloud/current/connectors/cc-http-source.html#cursor-pagination-offset-mode-with-the-gcs-list-objects-rest-api), [simple incrementing](https://docs.confluent.io/cloud/current/connectors/cc-http-source.html#simple-incrementing-offset-mode-with-the-atlassian-confluence-cloud-rest-api).
