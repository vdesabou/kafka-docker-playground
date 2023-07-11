# HTTP Sink connector



## Objective

Quickly test [HTTP Sink](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-sink-connector) connector.

This is based on [Kafka Connect HTTP Connector Quick Start](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-connector-quick-start)

The HTTP service is using [vdesabou/kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo).

Note: A great resource to test different HTTP status code is [http://httpstat.us](http://httpstat.us).

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

### JSON Converter Example

```bash
$ playground run -f http_json_basic_auth<tab>
```

Sending using:

```
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic json-topic << EOF
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

```bash
curl admin:password@localhost:9083/api/messages | jq .
[
  {
    "id": 1,
    "message": "[{\"complaint_type\":\"Dirty car\",\"new_customer\":false,\"trip_cost\":29.1,\"customer_name\":\"Ed\",\"number_of_rides\":22}]"
  }
]
```
### AVRO Converter Example

```
$ playground run -f http_avro_basic_auth<tab>
```

Sending using:

```bash
playground topic produce -t avro-topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF
```

Getting:

```
curl admin:password@localhost:9083/api/messages | jq .
[
  {
    "id": 1,
    "message": "[{\"f1\":\"value1\"}]"
  },
  {
    "id": 2,
    "message": "[{\"f1\":\"value2\"}]"
  },
  {
    "id": 3,
    "message": "[{\"f1\":\"value3\"}]"
  },
  {
    "id": 4,
    "message": "[{\"f1\":\"value4\"}]"
  },
  {
    "id": 5,
    "message": "[{\"f1\":\"value5\"}]"
  },
  {
    "id": 6,
    "message": "[{\"f1\":\"value6\"}]"
  },
  {
    "id": 7,
    "message": "[{\"f1\":\"value7\"}]"
  },
  {
    "id": 8,
    "message": "[{\"f1\":\"value8\"}]"
  },
  {
    "id": 9,
    "message": "[{\"f1\":\"value9\"}]"
  },
  {
    "id": 10,
    "message": "[{\"f1\":\"value10\"}]"
  }
]
```
