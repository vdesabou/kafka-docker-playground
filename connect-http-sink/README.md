# HTTP Sink connector

## Objective

Quickly test [HTTP Sink](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-sink-connector) connector.

This is based on [Kafka Connect HTTP Connector Quick Start](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-connector-quick-start)

The HTTP service is using [Kafka Connect HTTP Sink Demo App](https://github.com/confluentinc/kafka-connect-http-demo)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

## How to run


* Simple (No) Authentication

```
$ ./http_simple_auth.sh
```

* Basic Authentication

```
$ ./http_basic_auth.sh
```

* Oauth2 Authentication

```
$ ./http_oauth2_auth.sh
```

* SSL Authentication

**FIXTHIS** NOT WORKING:

Getting ```org.apache.kafka.connect.errors.RetriableException: javax.net.ssl.SSLPeerUnverifiedException: Certificate for <http-service-ssl-auth> doesn't match any of the subject alternative names: []``` because `http-service-ssl-auth` is using `localhost-keystore.jks` which is using `CN=localhost`, therefore from `connect` we don't have `localhost`CN

```
$ ./http_ssl_auth.sh
```
