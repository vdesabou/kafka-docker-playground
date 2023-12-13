# HTTP Sink connector


## Objective

Quickly test [HTTP Sink](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-sink-connector) connector.

This is based on [Kafka Connect HTTP Connector Quick Start](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-connector-quick-start)

The HTTP service is using [vdesabou/kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo) when authentication is used (except for OAUTH2), otherwise it use a simple http server where error code returned can be changed simply using:

```bash
log "Set webserver to reply with 503"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 503}' http://localhost:9006/set-response-error-code
```

You can also adjust response time to add delay:

```bash
log "Set webserver to reply with 2 seconds delay"
curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time
```

And also set json response to send back:

```bash
log "Set webserver to reply with {"message":"Hello, World!"} json body"
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body
```

## How to run


### No Authentication

```bash
$ playground run -f http_no_auth<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

### Basic Authentication

```bash
$ playground run -f http_basic_auth<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

### Oauth2 Authentication

```bash
$ playground run -f http_oauth2_auth<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

### SSL + Basic Authentication

```bash
$ playground run -f http_ssl_basic_auth<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```
### SSL Authentication (mutual TLS)

```bash
$ playground run -f http_mtls_auth<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```
