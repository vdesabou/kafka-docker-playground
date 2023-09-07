# HTTP Sink connector


## Objective

Quickly test [HTTP Sink](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-sink-connector) connector.

This is based on [Kafka Connect HTTP Connector Quick Start](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-connector-quick-start)

The HTTP service is using [vdesabou/kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo) when authentication is used, otherwise it use a simple http server where error code returned can be changed simply using:

```bash
log "Set webserver to reply with 503"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 503}' http://localhost:9006
```

## How to run


### No Authentication

```bash
$ playground run -f http_no_auth<tab>
```

### Basic Authentication

```bash
$ playground run -f http_basic_auth<tab>
```

### Oauth2 Authentication

```bash
$ playground run -f http_oauth2_auth<tab>
```

### SSL + Basic Authentication

```bash
$ playground run -f http_ssl_basic_auth<tab>
```
### SSL Authentication (mutual TLS)

```bash
$ playground run -f http_mtls_auth<tab>
```
