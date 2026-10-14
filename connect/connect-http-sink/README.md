# HTTP Sink connector

## Objective

Quickly test the [HTTP Sink](https://docs.confluent.io/kafka-connectors/http/current/overview.html) connector.

The HTTP endpoint is [vdesabou/kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo) for the basic auth, SSL and mTLS variants, and a small Node.js server (`httpserver/`, or `httpserver-oauth2/` for OAuth2) for the no-auth and OAuth2 variants.

## Prerequisites

With CP 8.0+, connector version 1.7.10 or later is required (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f http_no_auth.sh
```

| Script | Description |
| --- | --- |
| `http_no_auth.sh` | No authentication, JSON records posted to the simple `httpserver` |
| `http_basic_auth.sh` | Basic authentication (`auth.type=BASIC`) |
| `http_basic_auth-proxy.sh` | Basic authentication, through an nginx forward proxy (`http.proxy.host`/`http.proxy.port`) |
| `http_oauth2_auth.sh` | OAuth2 client credentials (`auth.type=OAUTH2`) against `httpserver-oauth2` |
| `http_ssl_basic_auth.sh` | HTTPS with truststore + basic authentication |
| `http_mtls_auth.sh` | HTTPS with mutual TLS (keystore + truststore, `auth.type=NONE`) |

## What the script does

1. Downloads `jcl-over-slf4j-2.0.7.jar` and copies it into the HTTP connector `lib` folder.
2. Starts the environment with the HTTP service matching the variant (and `nginx-proxy` for the proxy variant).
3. Produces 10 records to topic `http-messages` (strings, or JSON generated with faker for the no-auth and OAuth2 variants).
4. Sets `org.apache.http` log level to `TRACE` with `playground debug log-level set`.
5. Creates the HTTP Sink connector, with responses reported to `success-responses` / `error-responses`.
6. Verifies the result: either by calling the `/api/messages` endpoint of the demo service, or with `playground topic consume --topic success-responses --min-expected-messages 10`.

## Controlling the simple HTTP server

The `httpserver` used by `http_no_auth.sh` exposes endpoints on `localhost:9006` to change its behaviour, which is handy to reproduce error handling and retries.

Return a given HTTP status code:

```bash
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 503}' http://localhost:9006/set-response-error-code
```

Add a delay (in ms) to each response:

```bash
curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time
```

Set the JSON body returned:

```bash
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body
```
