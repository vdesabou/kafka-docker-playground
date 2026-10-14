# HTTP Sink V2 connector

## Objective

Quickly test the [HTTP Sink V2](https://docs.confluent.io/cloud/current/connectors/cc-http-sink-v2.html) fully managed connector, running as a self-managed connector.

## Prerequisites

Confluent employees only: the scripts use the fully managed connector zip `confluentinc-kafka-connect-http-v2-0.1.0-rc-acd8307-cloud.zip`, fetched with `get_3rdparty_file` (the script exits with an error if it cannot be retrieved). To use another build, export `CONNECTOR_ZIP` with the absolute path of the zip, or pass `--connector-zip`.

## How to run

```bash
playground run -f http_v2_no_auth.sh
```

| Script | Description |
| --- | --- |
| `http_v2_no_auth.sh` | No authentication, POST of JSON records to the simple `httpserver` |
| `http_v2_oauth2_auth.sh` | OAuth2 client credentials (`auth.type=OAUTH2`) against `httpserver-oauth2` |

## What the script does

1. Retrieves the connector zip, downloads `jcl-over-slf4j-2.0.7.jar` and copies it into the connector `lib` folder.
2. Starts the environment with the HTTP server.
3. Produces 10 JSON records (generated with faker) to topic `http-messages`.
4. Sets `org.apache.http` log level to `TRACE` and configures the HTTP server to reply with `200`.
5. Creates the `http-sink` connector (`io.confluent.connect.http.sink.GenericHttpSinkConnector`, one API `api1` on `http://httpserver:9006/`), with responses reported to `success-responses` / `error-responses`.
6. Verifies with `playground topic consume --topic success-responses --min-expected-messages 10`.

The simple HTTP server can be told to return a given status code, delay or body, see [HTTP Sink connector](../connect-http-sink/README.md#controlling-the-simple-http-server).
