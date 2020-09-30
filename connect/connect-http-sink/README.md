# HTTP Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-http-sink/asciinema.gif?raw=true)

## Objective

Quickly test [HTTP Sink](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-sink-connector) connector.

This is based on [Kafka Connect HTTP Connector Quick Start](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-connector-quick-start)

The HTTP service is using [Kafka Connect HTTP Sink Demo App](https://github.com/confluentinc/kafka-connect-http-demo)



## How to run


### Simple (No) Authentication

```bash
$ ./http_simple_auth.sh
```

### Basic Authentication

```bash
$ ./http_basic_auth.sh
```

### Oauth2 Authentication

```bash
$ ./http_oauth2_auth.sh
```

### SSL Authentication

```bash
$ ./http_ssl_auth.sh
```

### JSON Converter Example

```bash
$ ./http_json_basic_auth.sh
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
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  }
]
```

**FIXTHIS** output message is not valid JSON

### AVRO Converter Example

```
$ ./http_avro_basic_auth.sh
```

Sending using:

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic avro-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Getting:

```
curl admin:password@localhost:9083/api/messages | jq .
[
  {
    "id": 1,
    "message": "Struct{f1=value1}"
  },
  {
    "id": 2,
    "message": "Struct{f1=value2}"
  },
  {
    "id": 3,
    "message": "Struct{f1=value3}"
  },
  {
    "id": 4,
    "message": "Struct{f1=value4}"
  },
  {
    "id": 5,
    "message": "Struct{f1=value5}"
  },
  {
    "id": 6,
    "message": "Struct{f1=value6}"
  },
  {
    "id": 7,
    "message": "Struct{f1=value7}"
  },
  {
    "id": 8,
    "message": "Struct{f1=value8}"
  },
  {
    "id": 9,
    "message": "Struct{f1=value9}"
  },
  {
    "id": 10,
    "message": "Struct{f1=value10}"
  }
]
```
