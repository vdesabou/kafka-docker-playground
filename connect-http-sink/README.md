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

```
$ ./http_ssl_auth.sh
```

* JSON Converter Example

```
$ ./http_json_basic_auth.sh
```

Sending using:

```
docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic json-topic << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
```

Json data:

```json
{
    "customer_name": "Ed",
    "complaint_type": "Dirty car",
    "trip_cost": 29.1,
    "new_customer": false,
    "number_of_rides": 22
}
```

Getting:

```
curl admin:password@localhost:9080/api/messages | jq .
[
  {
    "id": 1,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  }
]
```

**FIXTHIS** output message is not valid JSON

