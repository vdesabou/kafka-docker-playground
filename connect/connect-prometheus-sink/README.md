# Prometheus Sink connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Prometheus Sink](https://docs.confluent.io/current/connect/kafka-connect-prometheus-metrics/index.html#prometheus-metrics-sink-connector-for-cp) connector.


## How to run

Simply run:

```
$ ./prometheus-sink.sh
```

## Details of what the script is doing


Sending messages to topic `test-topic`

```bash
$ NOW=$(date +%s)
$ docker exec -i -e NOW=$NOW connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-topic --property value.schema='{"name": "metric","type": "record","fields": [{"name": "name","type": "string"},{"name": "type","type": "string"},{"name": "timestamp","type": "long"},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"doubleValue", "type": "double"}]}}]}' << EOF
{"name":"kafka_gaugeMetric1", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric2", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric3", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
EOF
```

Creating Prometheus sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.prometheus.PrometheusMetricsSinkConnector",
               "tasks.max": "1",
               "confluent.topic.bootstrap.servers":"broker:9092",
               "confluent.topic.replication.factor": "1",
               "prometheus.scrape.url": "http://connect:8889/metrics",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url":"http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "key.converter.schemas.enable": "true",
               "value.converter.schemas.enable": "true",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.replication.factor": 1,
               "behavior.on.error": "LOG",
               "topics": "test-topic"
          }' \
     http://localhost:8083/connectors/prometheus-sink/config | jq .
```

Verify data is in Prometheus

```bash
$ curl 'http://localhost:9090/api/v1/query?query=kafka_gaugeMetric1'
```

Results:

```json
{
    "data": {
        "result": [
            {
                "metric": {
                    "__name__": "kafka_gaugeMetric1",
                    "instance": "connect:8889",
                    "job": "connect-metrics"
                },
                "value": [
                    1585572837.592,
                    "5.639623848362502"
                ]
            }
        ],
        "resultType": "vector"
    },
    "status": "success"
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
